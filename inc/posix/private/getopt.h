#ifndef _PRIVATE_GETOPT_H
#define _PRIVATE_GETOPT_H

struct z_getopt_r_context {
    char *optarg;
    int opterr;
    int optind;
    int optopt;
    int optcur;
};

int z_getopt_r(struct z_getopt_r_context *context, int argc, char *const argv[], const char *optstring);

extern char *optarg;
extern int opterr, optind, optopt;
int getopt(int argc, char *const argv[], const char *optstring);

#endif /* _PRIVATE_GETOPT_H */
