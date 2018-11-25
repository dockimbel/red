Red/System [
	Title:	"Socket implementation on Windows"
	Author: "Xie Qingtian"
	File: 	%socket.reds
	Tabs: 	4
	Rights: "Copyright (C) 2018 Red Foundation. All rights reserved."
	License: {
		Distributed under the Boost Software License, Version 1.0.
		See https://github.com/red/red/blob/master/BSL-License.txt
	}
]

#define AF_INET6	23

tcp-client: func [
	p		[red-object!]
	host	[red-string!]
	port	[red-integer!]
	/local
		fd	[integer!]
		n	[integer!]
		s	[c-string!]
][
	if null? g-poller [g-poller: poll/init]
	fd: socket/create AF_INET SOCK_STREAM IPPROTO_TCP

	n: -1
	s: unicode/to-utf8 host :n
	socket/connect p fd s port/value AF_INET
]

tcp-server: func [
	p		[red-object!]
	port	[red-integer!]
	/local
		fd	[integer!]
		acp [integer!]
][
	if null? g-poller [g-poller: poll/init]
	fd: socket/create AF_INET SOCK_STREAM IPPROTO_TCP
	socket/bind fd port/value AF_INET
	acp: socket/create AF_INET SOCK_STREAM IPPROTO_TCP
	socket/accept p fd acp
]

start-red-port: func [
	red-port	[red-object!]
	/local
		values	[red-value!]
		spec	[red-object!]
		host	[red-string!]
		p		[red-integer!]
		scheme	[red-word!]
][
	spec:	as red-object! (object/get-values red-port) + port/field-spec
	values: object/get-values spec
	scheme: as red-word! values				;-- TBD: check scheme
	host:	as red-string! values + 2
	p:		as red-integer! values + 3
	either TYPE_NONE = TYPE_OF(host) [		;-- start a tcp server
		tcp-server red-port p
	][
		tcp-client red-port host p
	]
]

store-iocp-data: func [
	data		[iocp-data!]
	red-port	[red-object!]
	/local
		values	 [red-value!]
		state	 [red-object!]	 
][
	values: object/get-values red-port
	state: as red-object! values + port/field-state
	integer/make-at (object/get-values state) + 1 as-integer data
]

create-red-port: func [
	sock		[integer!]
	return:		[red-object!]
	/local
		p		[red-object!]
		data	[iocp-data!]
][
	data: iocp/create-data sock
	sockdata/insert sock as int-ptr! data
	p: port/make none-value stack/push* TYPE_NONE
	store-iocp-data data p
	p
]

call-awake: func [
	red-port	[red-object!]
	msg			[red-object!]
	op			[iocp-op-code!]
	/local
		values	 [red-value!]
		awake	 [red-function!]
		event	 [red-event! value]
][
	values: object/get-values red-port
	awake: as red-function! values + port/field-awake
	event/header: TYPE_EVENT
	event/type: op
	event/msg: as byte-ptr! msg
	stack/mark-func words/_awake awake/ctx
	stack/push as red-value! event
	port/call-function awake awake/ctx
]

socket: context [

	create: func [
		family		[integer!]
		type		[integer!]
		protocal	[integer!]
		return:		[integer!]
		/local
			fd		[integer!]
	][
		fd: WSASocketW family type protocal null 0 1		;-- OVERLAPPED
		assert fd >= 0
		fd
	]

	bind: func [
		sock	[integer!]
		port	[integer!]
		type	[integer!]
		return: [integer!]
		/local
			saddr	[sockaddr_in! value]
			p		[integer!]
	][
		either type = AF_INET [		;-- IPv4
			p: htons port
			saddr/sin_family: p << 16 or type
			saddr/sin_addr: 0
			saddr/sa_data1: 0
			saddr/sa_data2: 0
			if 0 <> _bind sock as int-ptr! :saddr size? saddr [
				probe "bind fail"
			]
			listen sock 1024
			0
		][							;-- IPv6
			0
		]
	]

	accept: func [
		red-port [red-object!]
		sock	 [integer!]
		acpt	 [integer!]
		/local
			n		 [integer!]
			data	 [iocp-data!]
			AcceptEx [AcceptEx!]
	][
		data: as iocp-data! sockdata/get sock
		if null? data [
			data: iocp/create-data sock
			sockdata/insert sock as int-ptr! data
		]
		copy-cell as cell! red-port as cell! :data/cell
		store-iocp-data data red-port
		iocp/bind g-poller data

		set-memory as byte-ptr! data null-byte size? OVERLAPPED!
		if null? data/buffer [		;-- make address buffer
			data/buffer: alloc0 128
		]

		n: 0
		data/code: IOCP_OP_ACCEPT
		data/accept: acpt
		AcceptEx: as AcceptEx! AcceptEx-func
		unless AcceptEx sock acpt data/buffer 0 128 128 :n as int-ptr! data [
			;-- not ready yet, check it later in poll
			exit
		]
		probe "Accept ok"

		;-- do not post the completion notification as we're processing it now
		SetFileCompletionNotificationModes as int-ptr! acpt 1

		n: 1
		ioctlsocket acpt FIONBIO :n
		n: 1
		setsockopt acpt IPPROTO_TCP 1 as c-string! :n size? n		;-- TCP_NODELAY: 1

		call-awake red-port create-red-port acpt IOCP_OP_ACCEPT
	]

	connect: func [
		red-port	[red-object!]
		sock		[integer!]
		addr		[c-string!]
		port		[integer!]
		type		[integer!]
		/local
			n		[integer!]
			data	[iocp-data!]
			saddr	[sockaddr_in! value]
			ConnectEx [ConnectEx!]
	][
		data: as iocp-data! sockdata/get sock
		if null? data [
			data: iocp/create-data sock
			sockdata/insert sock as int-ptr! data
		]
		copy-cell as cell! red-port as cell! :data/cell
		store-iocp-data data red-port
		iocp/bind g-poller data

		set-memory as byte-ptr! data null-byte size? OVERLAPPED!

		either type = AF_INET [		;-- IPv4
			port: htons port
			saddr/sin_family: port << 16 or type
			saddr/sin_addr: 0
			saddr/sa_data1: 0
			saddr/sa_data2: 0
			if 0 <> _bind sock as int-ptr! :saddr size? saddr [
				probe "bind fail in connect"
			]
		][
			0
		]

		data/code: IOCP_OP_CONN
		n: 0
		saddr/sin_addr: inet_addr addr
		ConnectEx: as ConnectEx! ConnectEx-func
		unless ConnectEx sock as int-ptr! :saddr size? saddr null 0 :n as int-ptr! data [
			exit
		]

		probe "Connect ok"

		;-- do not post the completion notification as we're processing it now
		SetFileCompletionNotificationModes as int-ptr! sock 1
		call-awake red-port red-port IOCP_OP_ACCEPT
	]
]