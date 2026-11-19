#ifndef TYPE_REGEX_H
#define TYPE_REGEX_H

extern value type_regex(value f);
extern value type_rxsession(value f);
extern value Qregex(void *prog);
extern value Qrxsession(void *s);
extern value type_load_regex(value f);

#endif
