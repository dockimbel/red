Red/System [
	File: 	 %assembler.reds
	Tabs:	 4
	Rights:  "Copyright (C) 2024 Red Foundation. All rights reserved."
	License: "BSD-3 - https://github.com/red/red/blob/master/BSD-3-License.txt"
]

x86-regs: context [
	#enum gpr-reg! [
		none
		eax
		ecx
		edx
		ebx
		esp
		ebp
		esi
		edi
		r8
		r9
		r10
		r11
		r12
		r13
		r14
		r15
	]

	#enum sse-reg! [
		xmm0
		xmm1
		xmm2
		xmm3
		xmm4
		xmm5
		xmm6
		xmm7
		xmm8
		xmm9
		xmm10
		xmm11
		xmm12
		xmm13
		xmm14
		xmm15
	]
]

x86-addr!: alias struct! [
	base	[integer!]
	index	[integer!]
	scale	[integer!]
	disp	[integer!]
	ref		[val!]
]

#define MOD_DISP0 		00h
#define MOD_DISP8 		40h
#define MOD_DISP32		80h
#define MOD_REG 		C0h
#define MOD_BITS		C0h
#define REX_BYTE		40h
#define REX_W			08h
#define REX_R			04h
#define REX_X			02h
#define REX_B			01h
#define NO_REX			00h
#define PREFIX_W		66h

#define ABS_ADDR		7FFFFFF0h
#define REL_ADDR		7FFFFFF1h
#define ABS_FLAG		F0h
#define REL_FLAG		F1h

asm: context [

	rex-byte: 0

	#enum basic-op! [
		OP_ADD: 1
		OP_OR
		OP_ADC
		OP_SBB
		OP_AND
		OP_SUB
		OP_XOR
		OP_CMP
	]

	;;opcodes:	add  or adc sbb and sub xor cmp
	op-rm-r:  [01h 09h 11h 19h 21h 29h 31h 39h]
	op-r-rm:  [03h 0Bh 13h 1Bh 23h 2Bh 33h 3Bh]
	op-eax-i: [05h 0Dh 15h 1Dh 25h 2Dh 35h 3Dh]

	pos: func [return: [integer!]][
		program/code-buf/length
	]

	emit-b: func [b [integer!]][
		put-b program/code-buf b
	]

	emit-bb: func [b1 [integer!] b2 [integer!]][
		put-bb program/code-buf b1 b2
	]

	emit-bbb: func [b1 [integer!] b2 [integer!] b3 [integer!]][
		put-bbb program/code-buf b1 b2 b3
	]

	emit-d: func [d [integer!]][put-32 program/code-buf d]

	emit-bd: func [b [integer!] d [integer!]][
		put-b program/code-buf b
		put-32 program/code-buf d
	]

	emit-bbd: func [b1 [integer!] b2 [integer!] d [integer!]][
		put-bb program/code-buf b1 b2
		put-32 program/code-buf d
	]

	rex-r: func [
		r		[integer!]
		rex		[integer!]
		return: [integer!]
	][
		either r > 8 [rex][0]
	]

	rex-m: func [
		m		[x86-addr!]
		rex		[integer!]
		return: [integer!]
		/local
			idx [integer!]
	][
		idx: m/index
		either zero? m/base [
			switch m/scale [
				1 [rex-r idx rex]
				2 [rex-r idx REX_X or rex]
				default [rex-r idx REX_X]
			]
		][
			rex: rex-r m/base rex
			rex or rex-r idx REX_X
		]
	]

	emit-r: func [
		r		[integer!]
		x		[integer!]
	][
		emit-b MOD_REG or (x and 7 << 3) or (r - 1 and 7)
	]

	emit-b-r-x: func [
		b		[integer!]
		r		[integer!]
		x		[integer!]
	][
		emit-b b
		emit-r r x
	]

	emit-b-r-x-rex: func [
		b		[integer!]
		r		[integer!]
		x		[integer!]
		rex		[integer!]
	][
		rex: rex or rex-r r REX_B
		if rex <> 0 [emit-b REX_BYTE or rex]
		emit-b-r-x b r x
	]

	emit-r-i: func [		;-- register, immediate
		r		[integer!]
		i		[integer!]
		op		[basic-op!]
	][
		either any [i < -128 i > 127][
			either r = x86-regs/eax [
				emit-bd op-eax-i/op i
			][
				emit-b-r-x 81h r op - 1
				emit-d i
			]
		][
			emit-b-r-x 83h r op - 1
			emit-b i
		]
	]

	emit-offset: func [
		offset	[integer!]
		x		[integer!]
	][
		x: x and 7 << 3
		either offset = REL_ADDR [
			emit-bd x or 5 offset		;-- relative offset
		][
			emit-bbd x or 4 25h offset	;-- absolute offset
		]
	]

	emit-rm: func [			;-- [register + disp], memory address via register
		op		[integer!]
		reg		[integer!]
		m		[x86-addr!]
		/local
			modrm	[integer!]
			disp	[integer!]
			sib		[integer!]
	][
		modrm: op or (reg - 1)
		disp: m/disp
		case [
			reg = x86-regs/esp [
				sib: 24h	;-- bits: 00100100
				if zero? disp [
					emit-bb MOD_DISP0 or modrm sib
					exit
				]
				either any [disp < -128 disp > 127][
					emit-bbd MOD_DISP32 or modrm sib disp
				][
					emit-bbb MOD_DISP8 or modrm sib disp
				]
			]
			zero? disp [
				either reg = x86-regs/ebp [
					emit-bb MOD_DISP8 or modrm 0
				][
					emit-b MOD_DISP0 or modrm
				]
			]
			any [disp < -128 disp > 127][
				emit-bd MOD_DISP32 or modrm disp
			]
			true [
				emit-bb MOD_DISP8 or modrm disp
			]
		]
	]

	emit-m: func [
		m		[x86-addr!]	;-- memory location
		x		[integer!]	;-- ModR/M.reg
		/local
			base scale index disp modrm sib [integer!]
	][
		x: x and 7 << 3
		base: m/base
		index: m/index
		scale: m/scale
		disp: m/disp

		if zero? index [
			either zero? base [
				either disp = REL_ADDR [
					emit-bd x or 5 disp			;-- relative address
				][
					emit-bbd x or 4 25h disp	;-- absolute address
					record-abs-ref pos - 4 m/ref
				]
			][
				emit-rm x base m
			]
			exit
		]

		if zero? base [
			if scale = 1 [
				emit-rm x index m
				exit
			]
			if scale = 2 [	;-- convert to reg + reg
				scale: 1
				base: index
			]
		]

		modrm: x or (x86-regs/esp - 1)

		sib: index - 1 << 3
		sib: sib or case [
			scale = 2 [40h]
			scale = 4 [80h]
			scale = 8 [C0h]
			true [0]
		]

		either base <> 0 [
			sib: sib or (base - 1)
			modrm: modrm or case [
				any [disp < -128 disp > 127][MOD_DISP32]
				disp <> 0 [MOD_DISP8]
				any [base = x86-regs/ebp base = x86-regs/r13][MOD_DISP8]
				true [0]
			]
		][
			sib: sib or (x86-regs/ebp - 1)
		]

		case [
			any [zero? base disp < -128 disp > 127][
				emit-bbd modrm sib disp
			]
			modrm and C0h = MOD_DISP8 [
				emit-bbb modrm sib disp
			]
			true [emit-bb modrm sib]
		]
	]

	emit-b-m: func [
		b		[integer!]
		m		[x86-addr!]
		x		[integer!]
	][
		emit-b b
		emit-m m x
	]

	emit-b-m-x: func [
		op		[integer!]	;-- byte
		m		[x86-addr!]	;-- memory location
		x		[integer!]	;-- Mod/RM.reg
		rex		[integer!]	;-- rex byte
	][
		rex: rex or rex-m m REX_B
		if rex <> 0 [emit-b REX_BYTE or rex]
		emit-b op
		emit-m m x
	]

	emit-b-r-m: func [
		op		[integer!]
		r		[integer!]
		m		[x86-addr!]
		rex		[integer!]	;-- rex byte
		/local
			b	[integer!]
	][
		b: rex-r r REX_R
		b: b or rex-m m REX_B
		rex: rex or b
		if rex <> 0 [emit-b REX_BYTE or rex]
		emit-b-m op m r - 1
	]

	emit-b-m-r: func [
		op		[integer!]
		m		[x86-addr!]
		r		[integer!]
		rex		[integer!]	;-- rex byte
		/local
			b	[integer!]
	][
		b: rex-m m REX_B
		b: b or rex-r r REX_R
		rex: rex or b
		if rex <> 0 [emit-b REX_BYTE or rex]		
		emit-b-m op m r - 1
	]

	emit-b-r-r: func [
		op		[integer!]
		r1		[integer!]
		r2		[integer!]
		rex		[integer!]	;-- rex byte
		/local
			b	[integer!]
	][
		b: rex-r r1 REX_B
		b: b or rex-r r2 REX_R
		rex: rex or b
		if rex <> 0 [emit-b REX_BYTE or rex]
		emit-b-r-x op r1 r2
	]

	emit-r-r: func [
		r1		[integer!]
		r2		[integer!]
		op		[basic-op!]
		rex		[integer!]
	][
		emit-b-r-r op-rm-r/op r1 r1 rex
	]

	emit-r-m: func [
		r		[integer!]
		m		[x86-addr!]
		op		[basic-op!]
		rex		[integer!]
	][
		emit-b-r-m op-r-rm/op r m rex
	]

	emit-m-r: func [
		m		[x86-addr!]
		r		[integer!]
		op		[basic-op!]
		rex		[integer!]
	][
		emit-b-m-r op-rm-r/op m r rex
	]

	emit-m-i: func [
		m		[x86-addr!]
		i		[integer!]
		op		[basic-op!]
		rex		[integer!]
	][
		either any [i < -128 i > 127][
			emit-b-m-x 81h m op rex
			emit-d i
		][
			emit-b-m-x 83h m op rex
			emit-b i
		]
	]

	ret: does [emit-b C3h]

	jmp-rel: func [
		offset	[integer!]
	][
		either all [offset >= -126 offset <= 129][
			emit-bb EBh offset - 2
		][
			emit-bd E9h offset - 5
		]
	]

	jmp-label: func [
		l		[label!]
	][
		emit-bd E9h REL_ADDR
		record-label l pos - 4
	]

	jc-rel: func [
		cond	[integer!]
		offset	[integer!]
	][
		either all [offset >= -126 offset <= 129][
			emit-bb 70h + cond offset - 2
		][
			emit-bbd 0Fh 80h + cond offset - 6
		]	
	]

	jc-rel-label: func [
		cond	[integer!]
		l		[label!]
	][
		emit-bbd 0Fh 80h + cond REL_ADDR
		record-label l pos - 4
	]

	call-rel: func [
		offset	[integer!]
	][
		emit-bd E8h offset
	]

	icall-rel: func [		;-- absolute indirect call
		addr	[integer!]
	][
		emit-b FFh
		emit-offset addr 2
	]

	movd-r-m: func [
		r		[integer!]	;-- dst
		m		[x86-addr!]	;-- src
	][
		emit-b-r-m 8Bh r m NO_REX
	]

	movd-m-r: func [
		m		[x86-addr!]
		r		[integer!]
	][
		emit-b-m-r 89h m r NO_REX
	]

	movd-r-r: func [
		r1		[integer!]
		r2		[integer!]
	][
		emit-b-r-r 89h r1 r2 NO_REX
	]

	movd-m-i: func [
		m		[x86-addr!]
		imm		[integer!]
	][
		emit-b-m-x C7h m 0 NO_REX
		emit-d imm
	]

	movd-r-i: func [
		r		[integer!]
		imm		[integer!]
	][
		emit-b B8h + r
		emit-d imm
	]

	add-r-i: func [
		r		[integer!]
		imm		[integer!]
		rex		[integer!]
	][
		emit-r-i r imm OP_ADD rex
	]

	add-r-r: func [
		r1		[integer!]
		r2		[integer!]
		rex		[integer!]
	][
		emit-r-r r1 r2 OP_ADD rex
	]

	add-r-m: func [
		r		[integer!]
		m		[x86-addr!]
		rex		[integer!]
	][
		emit-r-m r m OP_ADD rex
	]

	add-m-r: func [
		m		[x86-addr!]
		r		[integer!]
		rex		[integer!]
	][
		emit-m-r m r OP_ADD rex
	]

	add-m-i: func [
		m		[x86-addr!]
		imm		[integer!]
		rex		[integer!]
	][
		emit-m-i m imm OP_ADD - 1 rex
	]

	cmp-r-i: func [
		r		[integer!]
		imm		[integer!]
		rex		[integer!]
	][
		emit-r-i r imm OP_CMP rex
	]

	cmpb-r-i: func [
		r		[integer!]
		imm		[integer!]
		/local
			rex [integer!]
	][
		either r = x86-regs/eax [
			emit-bb 3Ch imm
		][
			rex: either r > 8 [REX_BYTE][NO_REX]
			emit-b-r-x 80h r 7 rex
			emit-b imm
		]
	]
]

to-loc: func [
	o		[operand!]
	return: [integer!]
	/local
		d	[def!]
		u	[use!]
		w	[overwrite!]
][
	switch o/header and FFh [
		OD_DEF [
			d: as def! o
			d/constraint
		]
		OD_USE [
			u: as use! o
			u/constraint
		]
		OD_OVERWRITE [
			w: as overwrite! o
			w/constraint
		]
		default [
			probe ["wrong operand type: " o/header and FFh]
			0
		]
	]
]

to-imm: func [
	o		[operand!]
	return: [integer!]
	/local
		i	[immediate!]
		val [cell!]
		int [red-integer!]
		b	[red-logic!]
		f	[red-float!]
][
	i: as immediate! o
	val: i/value
	switch TYPE_OF(val) [
		TYPE_INTEGER [
			int: as red-integer! val
			int/value
		]
		TYPE_LOGIC [
			b: as red-logic! val
			as-integer b/value
		]
		TYPE_FLOAT [
			f: as red-float! val
			as integer! keep f
		]
		default [probe ["to-imm: " TYPE_OF(val)] 0]
	]
]

adjust-frame: func [
	frame	[frame!]
	add?	[logic!]
	/local
		n	[integer!]
		op	[integer!]
][
	n: frame/size - target/addr-size		;-- return addr already pushed
	if n > 0 [
		op: either add? [asm/OP_ADD][asm/OP_SUB]
		asm/emit-r-i x86-regs/esp n op
	]
]

make-addr: func [
	base	[integer!]
	index	[integer!]
	scale	[integer!]
	disp	[integer!]
	return: [x86-addr!]
	/local
		a	[x86-addr!]
][
	a: xmalloc(x86-addr!)
	a/base: base
	a/index: index
	a/scale: scale
	a/disp: disp
	a
]

loc-to-addr: func [						;-- location idx to memory addr
	loc		[integer!]
	addr	[x86-addr!]
	f		[frame!]
	r		[reg-set!]
	/local
		word-sz [integer!]
		offset	[integer!]
][
	loc: loc and (not FRAME_SLOT_64)	;-- remove flag
	offset: 0
	word-sz: target/addr-size
	case [
		loc >= r/callee-base [
			offset: word-sz * (loc - r/callee-base)
		]
		loc >= r/caller-base [
			offset: word-sz * (loc - r/caller-base) + f/size
		]
		loc >= r/spill-start [
			offset: word-sz * (loc - r/spill-start + f/spill-args)
		]
		true [probe ["invalid stack location: " loc]]
	]
	addr/base: x86-regs/esp
	addr/index: 0
	addr/scale: 1
	addr/disp: offset
]

rrsd-to-addr: func [
	p		[ptr-ptr!]
	addr	[x86-addr!]
	/local
		base	[integer!]
		index	[integer!]
		scale	[integer!]
		disp	[integer!]
		b		[operand!]
		i		[operand!]
		imm		[immediate!]
		val		[cell!]
][
	b: as operand! p/value
	base: either OPERAND_USE?(b) [to-loc b][0]
	p: p + 1
	i: as operand! p/value
	index: either OPERAND_USE?(i) [to-loc i][0]
	p: p + 1
	scale: to-imm as operand! p/value
	p: p + 1
	imm: as immediate! p/value
	val: imm/value
	switch TYPE_OF(val) [
		TYPE_ADDR [
			disp: ABS_ADDR
		]
		default [disp: 0]
	]
	addr/base: base
	addr/index: index
	addr/scale: scale
	addr/disp: disp
	addr/ref: as val! val
]

call-fn: func [v [cell!] /local fval [val!] f [fn!]][
	assert v/header = TYPE_FUNCTION

	fval: as val! v
	f: as fn! fval/ptr
	either NODE_FLAGS(f) and RST_IMPORT_FN = 0 [
		asm/call-rel REL_ADDR
	][
		asm/icall-rel REL_ADDR
	]
	record-fn-call f asm/pos - 4
]

assemble-op: func [
	op		[integer!]
	p		[ptr-ptr!]
	/local
		l	[label!]
		c	[integer!]
		f	[operand!]
		imm [immediate!]
][
	switch x86_OPCODE(op) [
		I_JMP [
			l: as label! p/value
			either l/pos >= 0 [
				asm/jmp-rel l/pos - asm/pos
			][
				asm/jmp-label l
			]
		]
		I_JC [
			l: as label! p/value
			c: x86_COND(op)
			either l/pos >= 0 [
				asm/jc-rel c l/pos - asm/pos
			][
				asm/jc-rel-label c l
			]
		]
		I_CALL [
			f: as operand! p/value
			switch OPERAND_TYPE(f) [
				OD_IMM [
					imm: as immediate! f
					call-fn imm/value
				]
				default [0]
			]
		]
		default [0]
	]
]

assemble-r-r: func [
	op		[integer!]
	a		[integer!]
	b		[integer!]
][
	switch op [
		I_MOVD [asm/movd-r-r a b]
		I_ADDD [asm/add-r-r a b NO_REX]
		default [0]
	]
]

assemble-r-m: func [
	op		[integer!]
	a		[integer!]
	m		[x86-addr!]
][
	switch op [
		I_MOVD [asm/movd-r-m a m]
		I_ADDD [asm/add-r-m a m NO_REX]
		default [0]
	]
]

assemble-r-i: func [
	op		[integer!]
	r		[integer!]
	imm		[integer!]
][
	switch op [
		I_MOVD [asm/movd-r-i r imm]
		I_ADDD [asm/add-r-i r imm NO_REX]
		I_CMPD [asm/cmp-r-i r imm NO_REX]
		I_CMPB [asm/cmpb-r-i r imm]
		default [0]
	]
]

assemble-m-i: func [
	op		[integer!]
	m		[x86-addr!]
	imm		[integer!]
][
	switch op [
		I_MOVD [asm/movd-m-i m imm]
		I_ADDD [asm/add-m-i m imm NO_REX]
		default [0]
	]
]

assemble-m-r: func [
	op		[integer!]
	m		[x86-addr!]
	a		[integer!]
][
	switch op [
		I_MOVD [asm/movd-m-r m a]
		I_ADDD [asm/add-m-r m a NO_REX]
		default [0]
	]
]

assemble: func [
	cg		[codegen!]
	i		[mach-instr!]
	/local
		op	[integer!]
		m	[integer!]
		reg [integer!]
		loc [integer!]
		imm [integer!]
		l	[label!]
		p	[ptr-ptr!]
		ins [integer!]
		rset [reg-set!]
		addr [x86-addr! value]
][
	rset: cg/reg-set
	ins: i/header
	op: x86_OPCODE(ins)
	p: as ptr-ptr! i + 1	;-- point to operands
	if op >= I_NOP [
		switch op [
			I_ENTRY [adjust-frame cg/frame no]
			I_BLK_BEG [
				l: as label! p/value
				l/pos: asm/pos
			]
			I_RET [
				adjust-frame cg/frame yes
				asm/ret
			]
			default [0]
		]
		exit
	]

	m: i/header >> AM_SHIFT and 1Fh
	switch m [
		_AM_NONE [assemble-op ins p]
		_AM_REG_OP [
			reg: to-loc as operand! p/value
			p: p + 1
			loc: to-loc as operand! p/value
			either gpr-reg?(loc) [
				assemble-r-r op reg loc
			][
				loc-to-addr loc :addr cg/frame rset
				assemble-r-m op reg :addr
			]
		]
		_AM_RRSD_REG [
			rrsd-to-addr p :addr
			p: p + 4
			reg: to-loc as operand! p/value
			assemble-m-r op :addr reg
		]
		_AM_RRSD_IMM [
			0
		]
		_AM_REG_RRSD [
			reg: to-loc as operand! p/value
			rrsd-to-addr p + 1 :addr
			assemble-r-m op reg :addr
		]
		_AM_OP [
			0
		]
		_AM_OP_IMM [
			loc: to-loc as operand! p/value
			p: p + 1
			imm: to-imm as operand! p/value
			either gpr-reg?(loc) [
				assemble-r-i op loc imm
			][
				loc-to-addr loc :addr cg/frame rset
				assemble-m-i op :addr imm
			]
		]
		_AM_OP_REG [
			loc: to-loc as operand! p/value
			p: p + 1
			reg: to-loc as operand! p/value
			either gpr-reg?(loc) [
				assemble-r-r op reg loc
			][
				loc-to-addr loc :addr cg/frame rset
				assemble-m-r op :addr reg
			]
		]
		_AM_XMM_REG
		_AM_XMM_OP
		_AM_OP_XMM
		_AM_XMM_RRSD
		_AM_RRSD_XMM
		_AM_XMM_IMM 
		_AM_REG_XOP
		_AM_XMM_XMM [0]
		default [0]
	]
]