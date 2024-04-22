#ifndef _PRIVATE_GETOPT_H
#define _PRIVATE_GETOPT_H

extern char *optarg;
extern int opterr, optind, optopt;
int getopt(int argc, char *const argv[], const char *optstring);

#endif /* _PRIVATE_GETOPT_H */
