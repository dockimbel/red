Red/System [
	File: 	 %lowering.reds
	Tabs:	 4
	Rights:  "Copyright (C) 2024 Red Foundation. All rights reserved."
	License: "BSD-3 - https://github.com/red/red/blob/master/BSD-3-License.txt"
]

lowering-env!: alias struct! [
	mark			[integer!]
	code			[byte-ptr!]
	data			[byte-ptr!]
	buffer			[dyn-array! value]	;-- dyn-array<instr!>
	new-instrs		[dyn-array! value]	;-- dyn-array<instr!>
	fn				[ir-fn!]
	cur-ctx			[ssa-ctx!]
	ssa-ctx			[ssa-ctx!]
	phis			[dyn-array! value]	;-- dyn-array<instr-phi!>
]

;-- Lowering SSA IR to machine-level IR
lowering: context [

	#define MARK_INS(i m) [
		i/mark: m
		i/link: null
	]

	map: func [
		old		[instr!]
		new		[instr!]
		env		[lowering-env!]
	][
		old/mark: env/mark
		old/link: new
		new/mark: env/mark
		replace-instr old new
		remove-instr old
	]

	map-keep: func [
		old		[instr!]
		new		[instr!]
		env		[lowering-env!]
	][
		old/mark: env/mark
		old/link: new
		new/mark: env/mark
		replace-instr old new
	]

	map-n-keep: func [
		"map old instr to multiple instrs in new. keep the old instr."
		old		[instr!]
		new		[ptr-array!]
		env		[lowering-env!]
		/local
			fn	[ir-fn!]
			p	[ptr-ptr!]
			pp	[ptr-ptr!]
			idx [integer!]
			rps	[dyn-array!]
			i	[instr!]
	][
		p: ARRAY_DATA(new)
		either new/length = 1 [
			map old as instr! p/value env
		][
			fn: env/fn
			old/link: null
			old/mark: fn/mark
			fn/mark: fn/mark + 1

			idx: old/mark - env/mark - 1
			rps: env/new-instrs 
			dyn-array/grow rps idx + 1
			pp: (as ptr-ptr! rps/data) + idx
			pp/value: as int-ptr! new
			if idx >= rps/length [rps/length: idx + 1]
			loop new/length [
				i: as instr! p/value
				i/mark: env/mark
				p: p + 1
			]
		]
	]

	map-n: func [
		"map old instr to multiple instrs in new"
		old		[instr!]
		new		[ptr-array!]	;-- array<instr!>
		env		[lowering-env!]
	][
		map-n-keep old new env
		kill-instr old
		remove-instr old
	]

	map-0: func [
		"map old instr to void instr"
		old		[instr!]
		env		[lowering-env!]
	][
		map-n old empty-array env
	]

	get-new-instrs: func [
		old		[instr!]
		env		[lowering-env!]
		return: [ptr-array!]
		/local
			p	[ptr-ptr!]
	][
		if old/mark = env/mark [return null]
		if old/mark > env/mark [
			p: ARRAY_DATA(env/new-instrs/data) + (old/mark - env/mark - 1)
			return as ptr-array! p/value
		]
		null
	]

	refresh-dests: func [
		edges	[ptr-array!]	;-- array<df-edge!>
		env		[lowering-env!]
		return: [ptr-array!]	;-- array<instr!>
		/local
			p	[ptr-ptr!]
			e	[df-edge!]
			old	[instr!]
			new [ptr-array!]
			i	[instr!]
			buf [dyn-array!]
	][
		buf: env/buffer
		dyn-array/clear buf
		p: ARRAY_DATA(edges)
		loop edges/length [
			e: as df-edge! p/value
			old: e/dst
			new: get-new-instrs old env
			either null? new [
				i: either old/link <> null [old/link][old]
				dyn-array/append buf as int-ptr! i
			][
				dyn-array/append-n buf new
			]
			p: p + 1
		]
		dyn-array/to-array buf
	]

	refresh-inputs: func [
		i		[instr!]
		env		[lowering-env!]
		/local
			new [ptr-array!]
	][
		new: refresh-dests i/inputs env
		ir-graph/set-inputs i new
	]

	gen-equal: func [
		i		[instr!]
		env		[lowering-env!]
	][
		refresh-inputs i env
	]

	gen-int-cmp: func [
		i		[instr!]
		env		[lowering-env!]
	][
		refresh-inputs i env
	]

	gen-truncate: func [
		i		[instr-op!]
		type	[int-type!]
		env		[lowering-env!]
		return: [instr!]
		/local
			w		[integer!]
			arith-w [integer!]
			trunc-i	[instr!]
			p		[ptr-ptr!]
			mark-return [subroutine!]
	][
		mark-return: [
			MARK_INS(i env/mark)
			return as instr! i
		]
		if INSTR_FLAGS(i) and F_NO_INT_TRUNC <> 0 [mark-return]
		ADD_INS_FLAGS(i F_NO_INT_TRUNC)

		w: INT_WIDTH(type)
		arith-w: config/int-width
		if w >= arith-w [mark-return]
		if all [
			config/int32-arith?
			w <= 32
		][
			if w = 32 [mark-return]
			arith-w: 32
		]

		env/cur-ctx/pt: i/next
		type: either arith-w = config/int-width [
			config/int-type
		][
			type-system/get-int-type arith-w false
		]
		trunc-i: ir-graph/add-int-cast i type as int-type! i/ret-type env/cur-ctx
		map-keep as instr! i trunc-i env
		;-- trunc-i's input changed by map-keep, we need to set it back
		p: ARRAY_DATA(trunc-i/inputs)
		update-uses as df-edge! p/value as instr! i
		;; XXX: Is below better than update-uses?
		;; e: as df-edge! p/value
		;; e/dst: as instr! i
		trunc-i
	]

	gen-truncate-op: func [
		i		[instr-op!]
		env		[lowering-env!]
	][
		refresh-inputs as instr! i env
		gen-truncate i as int-type! i/ret-type env
	]

	gen-op: func [
		i		[instr!]
		env		[lowering-env!]
		/local
			new [instr!]
	][
		new: i
		switch INSTR_OPCODE(i) [
			OP_INT_ADD
			OP_INT_SUB
			OP_INT_MUL			[gen-truncate-op as instr-op! i env]
			OP_INT_DIV			[0]
			OP_INT_MOD			[0]
			OP_INT_REM			[0]
			OP_INT_AND			[0]
			OP_INT_OR			[0]
			OP_INT_XOR			[0]
			OP_INT_SHL			[0]
			OP_INT_SAR			[0]
			OP_INT_SHR			[0]
			OP_INT_EQ			[gen-equal i env]
			OP_INT_NE			[0]
			OP_INT_LT			[gen-int-cmp i env]
			OP_INT_LTEQ			[gen-int-cmp i env]
			OP_FLT_ADD			[0]
			OP_FLT_SUB			[0]
			OP_FLT_MUL			[0]
			OP_FLT_DIV			[0]
			OP_FLT_MOD			[0]
			OP_FLT_REM			[0]
			OP_FLT_ABS			[0]
			OP_FLT_CEIL			[0]
			OP_FLT_FLOOR		[0]
			OP_FLT_SQRT			[0]
			OP_FLT_UNUSED		[0]
			OP_FLT_BITEQ		[0]
			OP_FLT_EQ			[0]
			OP_FLT_NE			[0]
			OP_FLT_LT			[0]
			OP_FLT_LTEQ			[0]
			OP_DEFAULT_VALUE	[0]
			OP_CALL_FUNC		[0]
			OP_GET_GLOBAL		[0]
			OP_SET_GLOBAL		[0]
			default [
				probe ["Internal Error: Unknown Opcode: " INSTR_OPCODE(i)]
			]
		]
		either i <> new [map i new env][MARK_INS(i env/mark)]
	]

	do-block: func [
		bb			[basic-block!]
		env			[lowering-env!]
		/local
			ctx		[ssa-ctx!]
			i		[instr!]
			code	[integer!]
	][
		ctx: env/cur-ctx
		ctx/closed?: no
		ctx/block: bb

		i: bb/next
		while [all [i <> null i <> bb]][
			code: INSTR_OPCODE(i)
			switch code [
				INS_PHI [0]
				INS_RETURN [0]
				default [
					either code >= OP_BOOL_EQ [
						env/cur-ctx/pt: i
						gen-op i env
					][
						0
					]
				]
			]
			i: i/next
		]
	]

	do-fn: func [
		fn		[ir-fn!]
		/local
			env		[lowering-env!]
			cur-ctx	[ssa-ctx! value]
			succs	[ptr-array!]
			i		[integer!]
			b		[basic-block!]
			e		[cf-edge!]
			pp		[ptr-ptr!]
			vec		[vector!]
	][
		ir-graph/init-ssa-ctx :cur-ctx null 0 null
		env: as lowering-env! malloc size? lowering-env!
		env/cur-ctx: :cur-ctx
		env/fn: fn
		dyn-array/init env/buffer 4
		dyn-array/init env/new-instrs 4
		env/mark: fn/mark + 1
		fn/mark: fn/mark + 2

		vec: vector/make size? int-ptr! 4
		vector/append-ptr vec as byte-ptr! fn/start-bb
		fn/start-bb/mark: env/mark
		i: 0
		while [i < vec/length][
			b: as basic-block! vector/pick-ptr vec i
			do-block b env
			succs: block-successors cur-ctx/block
			if succs <> null [
				pp: ARRAY_DATA(succs)
				loop succs/length [
					e: as cf-edge! pp/value
					b: e/dst
					if b/mark < env/mark [
						vector/append-ptr vec as byte-ptr! b
						b/mark: env/mark
					]
					pp: pp + 1
				]
			]
			i: i + 1
		]
		vector/destroy vec
	]
]