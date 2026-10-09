#include <stddef.h>
#include <stdio.h>
#include <sys/event.h>
#include <time.h>

#define FIELD(type, field) printf("(:" #type "-" #field " . %zu)\n", offsetof(struct type, field))
#define CONSTANT(name) printf("(:" #name " . %lld)\n", (long long)name)

int main(void) {
    puts("(");
    printf("(:kevent-size . %zu)\n", sizeof(struct kevent));
    FIELD(kevent, ident);
    FIELD(kevent, filter);
    FIELD(kevent, flags);
    FIELD(kevent, fflags);
    FIELD(kevent, data);
    FIELD(kevent, udata);
#ifdef __FreeBSD__
    FIELD(kevent, ext);
#endif
    printf("(:timespec-size . %zu)\n", sizeof(struct timespec));
    FIELD(timespec, tv_sec);
    FIELD(timespec, tv_nsec);
    CONSTANT(EVFILT_VNODE);
    CONSTANT(EVFILT_USER);
    CONSTANT(EV_ADD);
    CONSTANT(EV_ENABLE);
    CONSTANT(EV_CLEAR);
    CONSTANT(NOTE_TRIGGER);
    printf("(:note-vnode . %lld)\n", (long long)(NOTE_DELETE | NOTE_WRITE | NOTE_EXTEND |
           NOTE_ATTRIB | NOTE_LINK | NOTE_RENAME | NOTE_REVOKE));
    puts(")");
    return 0;
}
