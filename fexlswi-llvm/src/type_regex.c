/*
 * type_regex.c — tipo `regex` y tipo `rxsession` para Fexl.
 *
 * Envuelve los punteros opacos del motor de regex en valores Fexl con
 * reference counting: Qregex -> rx_program_destroy, Qrxsession ->
 * abregex_session_destroy. Sigue el patron de type_file.c / type_bn.c.
 *
 * Funciones registradas por load_regex():
 *
 *   (regex.compile pattern)        -> regex | void
 *   (regex.match prog text)        -> bool (o void si tipos incorrectos)
 *   (regex.search prog text from forward) -> num (offset o -1)
 *   (regex.count prog text)        -> num
 *   (regex.spans prog text max)    -> string "start,end;start,end;..."
 *   (is_regex x)                   -> bool
 *
 *   (abregex.session)              -> sesion nueva
 *   (abregex.define session defs)  -> bool (1 ok / 0 error de sintaxis)
 *   (abregex.compile session name) -> regex | void
 *   (is_rxsession x)               -> bool
 *
 * El patron y el texto son Fexl strings (type_str); str_data() da el ptr
 * y se usa strlen. El motor recibe (ptr, len) crudos, sin copias.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <str.h>
#include <value.h>
#include <basic.h>
#include <die.h>
#include <memory.h>

#include <type_num.h>
#include <type_regex.h>
#include <type_str.h>
#include <regex_abi.h>

/* ============ tipo regex (RxProgram*) ============ */

value type_regex(value f)
	{
	return type_void(f);
	}

static void clear_regex(value f)
	{
	rx_program_destroy(f->v_ptr);
	}

value Qregex(void *prog)
	{
	static struct value clear = {{.N=0}, {.clear=clear_regex}};
	return V(type_regex,&clear,(value)prog);
	}

/* ============ tipo rxsession (symtab abregex persistente) ============ */

value type_rxsession(value f)
	{
	return type_void(f);
	}

static void clear_rxsession(value f)
	{
	abregex_session_destroy(f->v_ptr);
	}

value Qrxsession(void *s)
	{
	static struct value clear = {{.N=0}, {.clear=clear_rxsession}};
	return V(type_rxsession,&clear,(value)s);
	}

/* ============ predicates ============ */

static value type_is_regex(value f)
	{
	return op_is_type(f,type_regex);
	}

static value type_is_rxsession(value f)
	{
	return op_is_type(f,type_rxsession);
	}

/* ============ regex.compile ============ */

static value type_regex_compile(value f)
	{
	value x = arg(f->R);
	if (x->T == type_str)
		{
		const char *pat = str_data(x);
		void *prog = regex_compile(pat,(long)strlen(pat));
		f = prog ? Qregex(prog) : hold(Qvoid);
		}
	else
		f = hold(Qvoid);
	drop(x);
	return f;
	}

/* ============ regex.match ============ */

static value type_regex_match(value f)
	{
	if (f->L->L == 0) return keep(f);
	{
	value x = arg(f->L->R);
	value y = arg(f->R);
	if (x->T == type_regex && y->T == type_str)
		{
		void *prog = x->v_ptr;
		const char *text = str_data(y);
		long tlen = (long)strlen(text);
		long s = rx_search_any(prog,text,tlen,0,1);
		f = boolean(s >= 0);
		}
	else
		f = hold(Qvoid);
	drop(x);
	drop(y);
	return f;
	}
	}

/* ============ regex.search (prog text from forward) ============ */

static value type_regex_search(value f)
	{
	/* 4 argumentos: se desenrollan con f->L->L->L->R, f->L->L->R, f->L->R, f->R */
	if (f->L->L == 0) return keep(f);
	if (f->L->L->L == 0) return keep(f);
	if (f->L->L->L->L == 0) return keep(f);
	{
	value p = arg(f->L->L->L->R);
	value t = arg(f->L->L->R);
	value vfrom = arg(f->L->R);
	value vfwd = arg(f->R);
	if (p->T == type_regex && t->T == type_str &&
	    vfrom->T == type_num && vfwd->T == type_num)
		{
		void *prog = p->v_ptr;
		const char *text = str_data(t);
		long tlen = (long)strlen(text);
		long from = (long)get_ulong(vfrom);
		int fwd = get_ulong(vfwd) != 0;
		f = Qnum((double)rx_search_any(prog,text,tlen,from,fwd));
		}
	else
		f = hold(Qvoid);
	drop(p); drop(t); drop(vfrom); drop(vfwd);
	return f;
	}
	}

/* ============ regex.count ============ */

static value type_regex_count(value f)
	{
	if (f->L->L == 0) return keep(f);
	{
	value p = arg(f->L->R);
	value t = arg(f->R);
	if (p->T == type_regex && t->T == type_str)
		{
		void *prog = p->v_ptr;
		const char *text = str_data(t);
		f = Qnum((double)rx_count(prog,text,(long)strlen(text)));
		}
	else
		f = hold(Qvoid);
	drop(p); drop(t);
	return f;
	}
	}

/* ============ regex.spans (prog text max) -> lista de pares ============ */

static value type_regex_spans(value f)
	{
	if (f->L->L == 0) return keep(f);
	if (f->L->L->L == 0) return keep(f);
	{
	value p = arg(f->L->L->R);
	value t = arg(f->L->R);
	value vmax = arg(f->R);
	if (p->T == type_regex && t->T == type_str && vmax->T == type_num)
		{
		void *prog;
		const char *text;
		char *buf;
		long tlen, max, n, i, off, used, cap;
		long *starts, *ends;
		prog = p->v_ptr;
		text = str_data(t);
		tlen = (long)strlen(text);
		max = (long)get_ulong(vmax);
		if (max < 0) max = 0;
		if (max > 1024) max = 1024;   /* tope defensivo */
		cap = (max ? max : 1) * 32 + 16;
		starts = malloc(sizeof(long) * (size_t)(max ? max : 1));
		ends = malloc(sizeof(long) * (size_t)(max ? max : 1));
		n = rx_spans(prog,text,tlen,starts,ends,max);
		buf = malloc((size_t)cap);
		off = 0; used = 0;
		for (i = 0; i < n; i++)
			{
			int k;
			k = snprintf(buf + off,(size_t)(cap - off),"%s%ld,%ld",
			             i ? ";" : "",starts[i],ends[i]);
			if (k < 0) break;
			off += k; used += k;
			if (used >= cap - 1) break;
			}
		f = Qstr(str_new_data(buf,(unsigned long)used));
		free(buf);
		free(starts);
		free(ends);
		}
	else
		f = hold(Qvoid);
	drop(p); drop(t); drop(vmax);
	return f;
	}
	}

/* ============ abregex.session ============ */

static value type_abregex_session(value f)
	{
	void *s = abregex_session_new();
	f = s ? Qrxsession(s) : hold(Qvoid);
	return f;
	}

/* ============ abregex.define (session defs) ============ */

static value type_abregex_define(value f)
	{
	if (f->L->L == 0) return keep(f);
	{
	value s = arg(f->L->R);
	value d = arg(f->R);
	if (s->T == type_rxsession && d->T == type_str)
		{
		const char *src = str_data(d);
		f = boolean(abregex_define_runtime(s->v_ptr,src,(long)strlen(src)) == 1);
		}
	else
		f = hold(Qvoid);
	drop(s); drop(d);
	return f;
	}
	}

/* ============ abregex.compile (session name) ============ */

static value type_abregex_compile(value f)
	{
	if (f->L->L == 0) return keep(f);
	{
	value s = arg(f->L->R);
	value n = arg(f->R);
	if (s->T == type_rxsession && n->T == type_str)
		{
		const char *name = str_data(n);
		void *prog = abregex_compile_runtime(s->v_ptr,name,(long)strlen(name));
		f = prog ? Qregex(prog) : hold(Qvoid);
		}
	else
		f = hold(Qvoid);
	drop(s); drop(n);
	return f;
	}
	}

/* ============ load ============ */

value type_load_regex(value f)
	{
	define("is_regex",Q(type_is_regex));
	define("is_rxsession",Q(type_is_rxsession));
	define("regex.compile",Q(type_regex_compile));
	define("regex.match",Q(type_regex_match));
	define("regex.search",Q(type_regex_search));
	define("regex.count",Q(type_regex_count));
	define("regex.spans",Q(type_regex_spans));
	define("abregex.session",Q0(type_abregex_session));
	define("abregex.define",Q(type_abregex_define));
	define("abregex.compile",Q(type_abregex_compile));
	return hold(QI);
	(void)f;
	}
