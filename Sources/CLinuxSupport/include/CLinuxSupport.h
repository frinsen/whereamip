#ifndef WHEREAMIP_CLINUXSUPPORT_H
#define WHEREAMIP_CLINUXSUPPORT_H

// Linux-only C helpers for WhereAmIPCore and the Linux indicator app. Kept to the two
// things Swift cannot reach on its own: glibc's resolver entry points (res_nquery is a
// macro over a versioned symbol, and its state struct must be zeroed and closed exactly
// so), and netlink, whose headers are not part of Swift's Glibc module.

/// Sends one DNS query for `name` (class IN, the given record type) through the system
/// resolver configuration in /etc/resolv.conf — on systemd-resolved machines that is the
/// local stub, i.e. the same path every application's lookups take. Writes the raw DNS
/// response into `answer` and returns its length, or -1 on any failure (NXDOMAIN and
/// timeouts included). Blocking; `timeout_seconds` bounds each attempt, with one retry.
int whereamip_res_query(const char *name, int record_type, int timeout_seconds,
                        unsigned char *answer, int answer_length);

/// Opens a NETLINK_ROUTE socket subscribed to link, address and route changes for both
/// address families. Returns the file descriptor (close-on-exec), or -1 on failure. Every
/// readable datagram means "something about the network changed".
int whereamip_netlink_route_socket(void);

#endif
