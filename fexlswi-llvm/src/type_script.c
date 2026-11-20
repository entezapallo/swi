/*
 * type_script.c — soporte de scripting para la consola de swi.
 *
 * El spec (seccion 8) pide: switches, booleanos e init tools.
 *
 * - booleanos: Fexl ya tiene T/F (load_basic). Se exponen como aliases
 *   `true` / `false` para los scripts de la consola.
 * - switch: un valor (nombre + estado booleano) que la TUI puede consultar.
 *   Se guarda en una tabla de sesion (operador `switch`). Como el intérprete
 *   es batch (fuera de la TUI), la tabla se persiste en un archivo que la
 *   TUI lee; aca solo se provee la semantica de encendido/apagado.
 * - init tools: el batch ya ejecuta un archivo al arrancar (argv). No hace
 *   falta codigo nuevo: es el comportamiento de fexl.c eval_script().
 *
 * Funciones registradas por load_script():
 *   (set_switch name on)  -> bool    (prende/apaga un switch, persistente)
 *   (get_switch name)     -> bool    (estado actual)
 *   (switch name on)      -> bool    (alias operador de set_switch)
 *   true / false          -> booleanos
 */

#include <stdio.h>
#include <string.h>

#include <str.h>
#include <value.h>
#include <basic.h>
#include <die.h>
#include <memory.h>
#include <type_num.h>
#include <type_str.h>
#include <type_script.h>

#define SWITCH_PATH "/tmp/swi_switches.txt"

/* --- persistencia simple de switches: nombre=0|1 por linea --- */

static int read_switch(const char *name)
	{
	FILE *f = fopen(SWITCH_PATH,"r");
	char line[256];
	int result = 0;
	if (!f) return 0;
	while (fgets(line,sizeof(line),f))
		{
		char *eq = strchr(line,'=');
		if (!eq) continue;
		*eq = 0;
		if (strcmp(line,name) == 0)
			{ result = (eq[1] == '1'); break; }
		}
	fclose(f);
	return result;
	}

static void write_switch(const char *name,int on)
	{
	/* tabla simple: un switch por linea "name=0|1". Leemos las existentes,
	 * reemplazamos la del nombre (o agregamos), reescribimos. */
	FILE *f;
	char lines[256][256];
	char names[256][256];
	int vals[256];
	int n = 0, i;
	f = fopen(SWITCH_PATH,"r");
	if (f)
		{
		while (n < 256 && fgets(lines[n],sizeof(lines[n]),f))
			{
			char *eq = strchr(lines[n],'=');
			if (eq)
				{
				*eq = 0;
				strncpy(names[n],lines[n],sizeof(names[n])-1);
				names[n][sizeof(names[n])-1] = 0;
				vals[n] = (eq[1] == '1');
				}
			n++;
			}
		fclose(f);
		}
	f = fopen(SWITCH_PATH,"w");
	if (!f) die("SWITCH_WRITE");
	for (i = 0; i < n; i++)
		if (strcmp(names[i],name) != 0)
			fprintf(f,"%s=%d\n",names[i],vals[i] ? 1 : 0);
	fprintf(f,"%s=%d\n",name,on ? 1 : 0);
	fclose(f);
	}

value type_script(value f)
	{
	return type_void(f);
	}

static value type_set_switch(value f)
	{
	if (f->L->L == 0) return keep(f);
	{
	value n = arg(f->L->R);
	value v = arg(f->R);
	if (n->T == type_str && v->T == type_num)
		{
		const char *name = str_data(n);
		int on = get_ulong(v) != 0;
		write_switch(name,on);
		f = boolean(1);
		}
	else
		f = hold(Qvoid);
	drop(n); drop(v);
	return f;
	}
	}

static value type_get_switch(value f)
	{
	value n = arg(f->R);
	if (n->T == type_str)
		f = boolean(read_switch(str_data(n)));
	else
		f = hold(Qvoid);
	drop(n);
	return f;
	}

value type_load_script(value f)
	{
	define("true",hold(QT));
	define("false",hold(QF));
	define("set_switch",Q(type_set_switch));
	define("get_switch",Q(type_get_switch));
	define("switch",Q(type_set_switch));
	return hold(QI);
	(void)f;
	}
