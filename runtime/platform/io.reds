Red/System [
	Title:	"low-level I/O facilities"
	Author: "Xie Qingtian"
	File: 	%io.reds
	Tabs: 	4
	Rights: "Copyright (C) 2015-2018 Red Foundation. All rights reserved."
	License: {
		Distributed under the Boost Software License, Version 1.0.
		See https://github.com/red/red/blob/master/BSL-License.txt
	}
]

#define SOCK_READBUF_SZ 8192			;-- 8KB
#define TLS_READBUF_SZ 16480			;-- 16384(16K) + 96

#enum iocp-type! [
	IOCP_TYPE_TCP:		0
	IOCP_TYPE_TLS:		1
	
	IOCP_TYPE_UDP:		2
	IOCP_TYPE_DNS:		3
	IOCP_TYPE_FILE:		4
]

#define IO_STATE_ERROR			0100h
#define IO_STATE_CLOSING		0200h
#define IO_STATE_CONNECTED		0400h
#define IO_STATE_TLS_DONE		1000h
#define IO_STATE_CLIENT			2000h
#define IO_STATE_READING		4000h
#define IO_STATE_WRITING		8000h
#define IO_STATE_PENDING_READ	4001h		;-- READING or EPOLLIN
#define IO_STATE_PENDING_WRITE	8004h		;-- WRITING or EPOLLOUT
#define IO_STATE_RW				5			;-- EPOLLIN or EPOLLOUT

make-sockaddr: func [
	saddr	[sockaddr_in!]
	addr	[c-string!]
	port	[integer!]
	type	[integer!]
	/local
		addr6 [sockaddr_in6!]
][
	port: htons port
	saddr/sin_family: port << 16 or type

	either type = AF_INET [
		saddr/sin_addr: saddr/sa_data1
		saddr/sa_data1: 0
		saddr/sa_data2: 0
	][
		addr6: as sockaddr_in6! saddr
		addr6/sin_flowinfo: 0
		addr6/sin_scope_id: 0
	]
]

#either OS = 'Windows [
	#include %windows/iocp.reds
	#include %windows/dns.reds
	#include %windows/tls.reds
	#include %windows/socket.reds
	;#include %windows/file.reds
][
	#include %POSIX/iocp.reds
	#include %POSIX/dns.reds
	#include %POSIX/tls.reds
	#include %POSIX/socket.reds
]