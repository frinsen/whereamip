#ifdef __linux__
#include "CLinuxSupport.h"

#include <arpa/nameser.h>
#include <linux/netlink.h>
#include <linux/rtnetlink.h>
#include <netinet/in.h>
#include <resolv.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

int whereamip_res_query(const char *name, int record_type, int timeout_seconds,
                        unsigned char *answer, int answer_length) {
    // A private resolver state per call: res_nquery on its own state is thread-safe, which
    // the shared `_res` behind plain res_query is not — the egress round runs six of these
    // in parallel.
    struct __res_state state;
    memset(&state, 0, sizeof state);
    if (res_ninit(&state) != 0) {
        return -1;
    }
    state.retrans = timeout_seconds > 0 ? timeout_seconds : 1;
    state.retry = 1;
    int length = res_nquery(&state, name, ns_c_in, record_type, answer, answer_length);
    res_nclose(&state);
    return length;
}

int whereamip_netlink_route_socket(void) {
    int fd = socket(AF_NETLINK, SOCK_RAW | SOCK_CLOEXEC, NETLINK_ROUTE);
    if (fd < 0) {
        return -1;
    }
    struct sockaddr_nl address;
    memset(&address, 0, sizeof address);
    address.nl_family = AF_NETLINK;
    address.nl_groups = RTMGRP_LINK | RTMGRP_IPV4_IFADDR | RTMGRP_IPV6_IFADDR
                      | RTMGRP_IPV4_ROUTE | RTMGRP_IPV6_ROUTE;
    if (bind(fd, (struct sockaddr *)&address, sizeof address) != 0) {
        close(fd);
        return -1;
    }
    return fd;
}
#endif
