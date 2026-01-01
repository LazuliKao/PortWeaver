#ifndef POSIX_MISSING_FIX_H
#define POSIX_MISSING_FIX_H

#ifdef _WIN32
// Only define these placeholders on Windows where they're missing
typedef struct
{
    int __dummy;
} sigset_t;

typedef struct
{
    int __dummy;
} siginfo_t;

struct sigaction
{
    void (*sa_handler)(int);
    void (*sa_sigaction)(int, siginfo_t *, void *);
    sigset_t sa_mask;
    int sa_flags;
};

#define _SC_PAGESIZE 1001
extern unsigned long sysconf(int name);
#endif

#endif // POSIX_MISSING_FIX_H