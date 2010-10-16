(*pp camlp4o -I $PIQI_ROOT/camlp4 pa_labelscope.cmo pa_openin.cmo *)
(*
   Copyright 2009, 2010 Anton Lavrik

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
*)


(*
 * Light syntax for Piqi DDL: Piqi to Piqi-light pretty-printer
 *)


module C = Piqi_common
open C
open Iolist


let gen_typeref (t:T.typeref) =
  match t with
    | `name x -> ios x
    | (#T.piqtype as t) ->
        (* generate name for built-in types *)
        (ios "." ^^ ios (piqi_typename t))


let gen_name_typeref name typeref =
  match name, typeref with
    | Some n, None -> ios n
    | None, Some t -> ios ":" ^^ gen_typeref t
    | Some n, Some t -> ios n ^^ ios " :" ^^ gen_typeref t
    | _ -> assert false


let gen_default = function
  | None -> iol [] (* there is no default *)
  | Some {T.Any.ast = Some ast} ->
      let str = Piq_gen.to_string ast in
      if String.contains str '\n' (* multiline? *)
      then
        let lines = Piq_gen.split_text str in
        let lines = List.map ios lines in
        iol [
          ios " ="; indent;
            iod "\n" lines;
          unindent;
        ]
      else
        iol [ ios " = "; ios str; ]
  | _ ->
      assert false


let gen_field_mode = function
    | `required -> "-"
    | `optional -> "?"
    | `repeated -> "*"


let gen_field x =
  let open F in
  let field_mode = gen_field_mode x.mode in
  iol [
    ios field_mode; ios " "; gen_name_typeref x.name x.typeref;
    gen_default x.default;
  ]


let gen_record x =
  let open R in
  let fields = List.map gen_field x.field in
  iol [
    ios "type "; ios x.name; ios " = record"; indent;
      iod "\n" fields;
    unindent;
  ]


let gen_option x =
  let open O in
  iol [
    ios "| "; gen_name_typeref x.name x.typeref
  ]


let gen_enum x =
  let open E in
  let options = List.map gen_option x.option in
  iol [
    ios "type "; ios x.name; ios " = enum"; indent;
      iod "\n" options; (* XXX: print on the same line? *)
    unindent;
  ]


let gen_variant x =
  let open V in
  let options = List.map gen_option x.option in
  iol [
    ios "type "; ios x.name; ios " = variant"; indent;
      iod "\n" options; (* XXX: try to print on the same line? *)
    unindent;
  ]


let gen_list x =
  let open L in
  let typename = gen_typeref x.typeref in
  iol [
    ios "type "; ios x.name; ios " = list :"; typename;
  ]


let gen_alias x =
  let open A in
  let typename = gen_typeref x.typeref in
  iol [
    ios "type "; ios x.name; ios " = :"; typename;
  ]


let gen_def = function
  | `record t -> gen_record t
  | `variant t -> gen_variant t
  | `enum t -> gen_enum t
  | `list t -> gen_list t
  | `alias t -> gen_alias t


let gen_sep l =
  if l <> [] then ios "\n\n" else iol []


let gen_defs (defs:T.piqdef list) =
  let l = List.map gen_def defs in
  iol [
    iod "\n\n" l; gen_sep l
  ]


let gen_import x =
  let open Import in
  let name =
    match x.name with
      | None -> iol []
      | Some x -> ios " as " ^^ ios x
  in
  iol [
    ios "import "; ios x.modname; name;
  ]


let gen_imports l =
  let l = List.map gen_import l in
  iol [
    iod "\n" l; gen_sep l
  ]


let gen_includes l =
  let open Includ in
  let l = List.map (fun x -> ios "include " ^^ ios x.modname) l in
  iol [
    iod "\n" l; gen_sep l
  ]


let _find_def name =
  let x = List.find
    (function
      | `record {Record.name = n} when n = name -> true
      | _ -> false) T.piqdef_list
  in
  (x :> T.piqtype)

let field_def = _find_def "field"
let option_def = _find_def "option"


let gen_extension_item x =
  let ast =
    match x with
      | {T.Any.ast = Some ast} -> ast
      | _ -> assert false
  in
  (* NOTE: recognizing and printing only fields and options *)
  match ast with
  | `named {T.Named.name = "field"; T.Named.value = ast} ->
      let x = Piqi.mlobj_of_ast field_def T.parse_field ast in
      let res = gen_field x in
      [res]
  | `named {T.Named.name = "option"; T.Named.value = ast} ->
      let x = Piqi.mlobj_of_ast option_def T.parse_option ast in
      let res = gen_option x in
      [res]
  | _ -> []


let gen_extension x =
  let open Extend in
  (* TODO: break long list of extended names to several lines *)
  let names = List.map ios x.name in
  let items = flatmap gen_extension_item x.quote in
  iol [
    ios "extend "; iod " " names; indent;
      iod "\n" items;
    unindent;
  ]


let gen_extensions l =
  let l = List.map gen_extension l in
  iol [
    iod "\n\n" l; gen_sep l
  ]


let gen_module = function
  | Some x -> ios "module " ^^ ios x ^^ ios "\n\n"
  | None -> iol []


let gen_piqi ch (piqi:T.piqi) =
  let open P in
  let piqi = some_of piqi.original_piqi in
  let code =
    iol [
      gen_module piqi.modname;
      gen_imports piqi.import;
      gen_includes piqi.includ;
      gen_defs piqi.piqdef;
      gen_extensions piqi.extend;
    ]
  in
  Iolist.to_channel ch code


let print_piqi_file ch filename =
  let piqi = Piqi.load_piqi filename in
  gen_piqi ch piqi


module Main = Piqi_main
open Main

let usage = "Usage: piqi light [options] [<.piqi file>] [output-file]\nOptions:"

let speclist = Main.common_speclist @
  [
    arg_o;
  ]


let run () =
  Main.parse_args () ~speclist ~usage ~min_arg_count:0 ~max_arg_count:2;
  let ch = Main.open_output !ofile in
  print_piqi_file ch !ifile


let _ =
  Main.register_command run "light"
    "pretty-print %.piqi using Piqi-light syntax"

