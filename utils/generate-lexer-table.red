Red [
	Title:   "Generates low-level lexer table"
	Author:  "Nenad Rakocevic"
	File: 	 %generate-lexer-tables.r
	Tabs:	 4
	Rights:  "Copyright (C) 2019 Red Foundation. All rights reserved."
	License: "BSD-3 - https://github.com/red/red/blob/master/BSD-3-License.txt"
	Note: {
		Outputs: %runtime/lexer-transitions.reds
	}
]

context [
	states: [
	;-- State ------------- Predicted type ----
		S_START				TYPE_VALUE			;-- 0
		S_LINE_CMT			TYPE_VALUE			;-- 1
		S_LINE_STR			TYPE_STRING			;-- 2
		S_SKIP_STR			TYPE_STRING			;-- 3
		S_M_STRING			TYPE_STRING			;-- 4
		S_SKIP_MSTR			TYPE_STRING			;-- 5
		S_FILE_1ST			TYPE_FILE			;-- 6
		S_FILE				TYPE_FILE			;-- 7
		S_FILE_HEX1			TYPE_FILE			;-- 8
		S_FILE_HEX2			TYPE_FILE			;-- 9
		S_FILE_STR			TYPE_FILE			;-- 10
		S_HDPER_ST			TYPE_STRING			;--	11
		S_HERDOC_ST			TYPE_STRING			;--	12
		S_HDPER_C0			TYPE_STRING			;--	13
		S_HDPER_CL			TYPE_STRING			;--	14
		S_SLASH				TYPE_REFINEMENT		;-- 15
		S_SLASH_N			TYPE_WORD			;-- 16
		S_SHARP				TYPE_ISSUE			;-- 17
		S_BINARY			TYPE_BINARY			;-- 18
		S_LINE_CMT2			TYPE_VALUE			;-- 19
		S_CHAR				TYPE_CHAR			;-- 20
		S_SKIP_CHAR			TYPE_CHAR			;-- 21
		S_CONSTRUCT			TYPE_VALUE			;-- 22
		S_ISSUE				TYPE_ISSUE			;-- 23
		S_NUMBER			TYPE_INTEGER		;-- 24
		S_DOTNUM			TYPE_FLOAT			;-- 25
		S_DECIMAL			TYPE_FLOAT			;-- 26
		S_DECEXP			TYPE_FLOAT			;--	27
		S_DECX				TYPE_FLOAT			;-- 28
		S_DEC_SPECIAL		TYPE_FLOAT			;-- 29
		S_TUPLE				TYPE_TUPLE			;-- 30
		S_DATE				TYPE_DATE			;-- 31
		S_TIME_1ST			TYPE_TIME			;-- 32
		S_TIME				TYPE_TIME			;-- 33
		S_PAIR_1ST			TYPE_PAIR			;-- 34
		S_PAIR				TYPE_PAIR			;-- 35
		S_MONEY_1ST			TYPE_MONEY			;-- 36
		S_MONEY				TYPE_MONEY			;-- 37
		S_MONEY_DEC			TYPE_MONEY			;-- 38
		S_HEX				TYPE_INTEGER		;-- 39
		S_HEX_END			TYPE_WORD			;--	40
		S_HEX_END2			TYPE_INTEGER		;--	41
		S_LESSER			TYPE_TAG			;-- 42
		S_TAG				TYPE_TAG			;-- 43
		S_TAG_STR			TYPE_TAG			;-- 44
		S_TAG_STR2			TYPE_TAG			;-- 45
		S_SIGN				TYPE_WORD			;-- 46
		S_DOTWORD			TYPE_WORD			;-- 47
		S_DOTDEC			TYPE_FLOAT			;-- 48
		S_WORD_1ST			TYPE_WORD			;--	49
		S_WORD				TYPE_WORD			;-- 50
		S_WORDSET			TYPE_SET_WORD		;-- 51
		S_URL				TYPE_URL			;-- 52
		S_EMAIL				TYPE_EMAIL			;-- 53
		S_PATH				TYPE_PATH			;-- 54
		S_PATH_NUM			TYPE_INTEGER		;--	55
		S_PATH_W1ST			TYPE_WORD			;-- 56
		S_PATH_WORD			TYPE_WORD			;-- 57
		S_PATH_SHARP		TYPE_ISSUE			;--	58
		S_PATH_SIGN			TYPE_WORD			;--	59
		--EXIT_STATES--		-					;-- 60
		T_EOF				-					;-- 61
		T_ERROR				TYPE_ERROR			;-- 62
		T_BLK_OP			-					;-- 63
		T_BLK_CL			-					;-- 64
		T_PAR_OP			-					;-- 65
		T_PAR_CL			-					;-- 66
		T_MSTR_OP			-					;-- 67
		T_MSTR_CL			TYPE_STRING			;-- 68
		T_MAP_OP			-					;-- 69
		T_PATH				-					;-- 70
		T_CONS_MK			-					;-- 71
		T_CMT				-					;-- 72
		T_STRING			TYPE_STRING			;-- 73
		T_WORD				TYPE_WORD			;-- 74
		T_ISSUE				TYPE_ISSUE			;-- 75
		T_INTEGER			TYPE_INTEGER		;-- 76 
		T_REFINE			TYPE_REFINEMENT		;-- 77
		T_CHAR				TYPE_CHAR			;-- 78
		T_FILE				TYPE_FILE			;-- 79
		T_BINARY			TYPE_BINARY			;-- 80
		T_PERCENT			TYPE_PERCENT		;-- 81
		T_FLOAT				TYPE_FLOAT			;-- 82
		T_FLOAT_SP			TYPE_FLOAT			;-- 83
		T_TUPLE				TYPE_TUPLE			;-- 84
		T_DATE				TYPE_DATE			;-- 85
		T_PAIR				TYPE_PAIR			;-- 86
		T_TIME				TYPE_TIME			;-- 87
		T_MONEY				TYPE_MONEY			;-- 88
		T_TAG				TYPE_TAG			;-- 89
		T_URL				TYPE_URL			;-- 90
		T_EMAIL				TYPE_EMAIL			;-- 91
		T_HEX				TYPE_INTEGER		;-- 92
		T_RAWSTRING			TYPE_STRING			;-- 93
	]

	CSV-table: %../docs/lexer/lexer-FSM.csv
	;-- Read states from CSV file
	csv: read CSV-table

	;-- Determine CSV separator
	sep: [#";" 0 #"," 0]
	parse csv [some [#";" (sep/2: sep/2 + 1) | #"," (sep/4: sep/4 + 1) | skip]]
	sort/skip/all/compare sep 2 func [a b][a/2 > b/2]

	;-- Decode CSV
	matrix: load-csv/with read CSV-table first sep

	;-- Generate the lexer table content
	table: make binary! 2000
	
	foreach line next matrix [
		out: make block! 50	
		foreach s next line [
			either pos: find/skip states to-word s  2[
				append out (index? pos) + 1 / 2 - 1
			][
				do make error! form reduce ["Error: state" s "not found"]
			]
		]
		append/only table out
	]
	
	;-- Generate the type-table content
	type-table: make binary! 2000
	types: load %../runtime/macros.reds
	types: select types 'datatypes!
	
	foreach [s t] states [append type-table either t = '- [0][(index? find types t) - 1]]

	;-- Template --
	
	template: compose/deep [Red/System [
		Note: "Auto-generated lexical scanner transitions table"
	]
	
	#enum lex-states! [
		(extract states 2)
	]
	
	type-table: (type-table)
		
	transitions: (table)
	]

	write %../runtime/lexer-transitions.reds mold/only template
]
()