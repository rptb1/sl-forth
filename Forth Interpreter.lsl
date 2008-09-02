// Forth Interpreter
//
// Copyright 2008 Richard Brooksby
// Written on the evening of 2008-01-14.
//
// This is a very simple threaded interpreter for a stack-based language
// which is a kind of Forth
// <http://en.wikipedia.org/wiki/Forth_(programming_language)>.
//
// Each line of the program is split into "segments" delimited by double
// quotes.    Alternate segments are words to be interpreted, and strings
// to be pushed on to the stack.  The word segments are split into words
// delimeted by spaces.     Words that start with digits are assumed to be
// integers (any trailing junk is discarded) to be pushed on to the stack.
// Other words are looked up in the dictionary and either executed or
// compiled, depending on the current mode.
//
// Dictionary is a list of triples: name, entry point, flags
// Currently the only flag is "immediate" which means the word
// will be executed immediately even if in compilation mode.
//
// Opcodes >= 0 call into the nodes list.
// (-99,-1) are reserved for internal operations
// -1 = return
// -2 = literal integer
// -3 = literal string
// -50 = define word
// -51 = end word definition
// Opcodes <= -100 cause link messages and the interpreter waits
// for a reply.     The operand stack is packed up in the link message string
// separated by vertical bars ("|") and the reply should have a number of
// -1 and a replacement stack similarly packed.     The key is not used.
//
// TODO
// 1. There could be a stack of program notecards and notecard lines, so
//      that programs could execute each other.  This would be easy to add.
// 2. The interpreter does not listen for commands until it has finished
//    compiling the notecards, but it should listen to out-of-band commands
//    to stop or reset etc.
// 3. If there is an error compiling the notecard the interpreter just stops
//    and does not listen for commands.  It has to be reset to fix the
//    the problem.
// 4. The interpreter should perhaps only listen for a limited period when
//    it is touched, like hippoINVENTORY, to reduce server lag when it is not
//    in use.
// 5. The listen channel and other options should be configurable via a
//    notecard in case the interpreter is given away without permission to
//    alter it.
// 6. There should perhaps be a way of dumping the compiled nodes and
//    dictionary to a script which could also be protected so that Forth
//    developers can give away unmodifiable compiled Forth systems.
// 7. There are no branching or looping structures and these can't be
//    provided by outside libraries.

string script;                  // Script name
key script_key;                 // This script's key 
integer version = 208;          // Script version
integer debug = 0;              // Debugging level, 0 for none

string program = "Forth Program"; // Program notecard name or empty for none.
string lib_prefix = "Forth Library "; // Library script name prefix
list lib_scripts;               // Potential library scripts
list libs;                      // Registered library scripts

integer program_line;           // Next line to read from notecard
key program_query;              // Dataserver query for reading line
list segs;                      // String/non-string segments
integer seg_index;              // Index of next segment to process
list words;                     // Words
integer word_index;             // Index of next word to process
list nodes;                     // Compiled instructions, index by "dict"
list rands;                     // Operand (parameter) stack
list rators;                    // Operator (return, linkage) stack
integer pc = -1;                // Program counter, indexes "nodes".
integer compiling;              // Are we compiling or executing?
integer running;             	// Are we running?
integer listen_channel = 3;     // Channel to listen for commands
integer listen_handle;          // Listen handle for further commands

// Nucleus dictionary
// It's possible to make a more primitive nucleus with things like
// "HERE", "'", ",", etc. in it and define things in terms of that
// but that's not really the use of this interpreter.
list dict = [
    ":", -50, FALSE,            // Define word
    ";", -51, TRUE              // End word definition
];

info(string message) {
	llOwnerSay((string)llGetLinkNumber() + " " + script + ": " + message);
}

error(string message) {
	info("ERROR: " + message);
}

trace(integer level, string message) {
    if(debug > level)
        info(message);
}

push_integer(integer i) {
    // See <http://talirosca.wikidot.com/list-optimization> for this idiom.
    // Not yet tested that it works with stacks though!
    // May not be needed since Mono, but no conclusions yet.  2008-09-02.
    rands = (rands=[]) + [i] + rands;
}

push_string(string s) {
    rands = (rands=[]) + [s] + rands;
}

integer pop_integer() {
    integer i = llList2Integer(rands, 0);
    rands = llDeleteSubList(rands, 0, 0);
    return i;
}

string pop_string() {
    string s = llList2String(rands, 0);
    rands = llDeleteSubList(rands, 0, 0);
    return s;
}

ret() {
    // trace(1, "ret from pc = " + (string)pc + " rators = " + llDumpList2String(rators, " "));
    // Safety check: may be able to remove
    if(rators == []) {
        error("Internal error: empty operator stack!");
        dump();
        abort();
        return;
    }
    pc = llList2Integer(rators, 0);
    rators = llDeleteSubList(rators, 0, 0);
}

compile_integer(integer i) {
    nodes = (nodes=[]) + nodes + [i];
}

compile_list(list l) {
    nodes = (nodes=[]) + nodes + l;
}

compile_string(string s) {
    nodes = (nodes=[]) + nodes + [s];
}

dump() {
    info("pc = " + (string)pc);
    info("rands = " + llDumpList2String(rands, " "));
    info("rators = " + llDumpList2String(rators, " "));
    info("words = " + llDumpList2String(words, " "));
    info("word index = " + (string)word_index);
    info("segs = " + llDumpList2String(segs, " "));
    info("seg index = " + (string)seg_index);
    info("program = " + program);
    info("program line = " + (string)program_line);
    info("dict = " + llDumpList2String(dict, " "));
    info("nodes = " + llDumpList2String(nodes, " "));
    info("compiling = " + (string)compiling);
    info((string)llGetFreeMemory() + " bytes free");
}

abort() {
    segs = [];
    seg_index = 0;
    words = [];
    word_index = 0;
    program = "";
    compiling = FALSE;
}

run() {
	running = TRUE;

    // LSL can't have more than one jump to each label or it ignores the
    // jumps!  Unbelievable.
@next0; @next1; @next2; @next3; @next4;
    // trace(1, "step pc = " + (string)pc + " rators = " + llDumpList2String(rators, "|"));

    if(pc >= 0) {                // Executing compiled code?
    @next_op0; @next_op1;
        integer op = llList2Integer(nodes, pc++);
        if(op < 0) {            // Special in-line opcode?
            if(op == -1) {        // return
                ret();
                jump next0;
            }
            if(op == -2) {        // literal integer
                push_integer(llList2Integer(nodes, pc++));
                jump next_op0;
            }
            if(op == -3) {        // literal string
                push_string(llList2String(nodes, pc++));
                jump next_op1;
            }
            // Fall through if unrecognized negative op.
        }
        // Ordinary threaded call
        // trace(1, "call " + (string)op);
        rators = (rators=[]) + [pc] + rators;
        pc = op;
        jump next1;
    }
    
    // If pc is -1 then we are returning to the interpreter after making
    // an immediate call from the compiler.

    if(pc != -1) {                // Built-in or external function
        if(pc == -50) {            // ":", define word
            string word = pop_string();
            trace(1, "Defining word " + word);
            dict = (dict=[]) + dict +
                   [word, llGetListLength(nodes), FALSE];
            compiling = TRUE;
            ret();
            jump next2;
        }
        if(pc == -51) {            // ";", end word definition
            compile_integer(-1); // append return opcode
            compiling = FALSE;
            ret();
            jump next3;
        }
        // External call
        // trace(1, "ecall pc = " + (string)pc + " rators = " + llDumpList2String(rators, " "));
        llMessageLinked(LINK_THIS, pc, llDumpList2String(rands, "|"), script_key);
        return;                    // Wait for reply
    }
    
@next_word0; @next_word1;

    // Interpret words until they are exhausted.
    integer word_count = llGetListLength(words);
    while(word_index < word_count) {
        string word = llList2String(words, word_index++);
        // Since there is only one string column in dict this won't
        // accidentally find the wrong things.  TODO: Unless a word is defined
        // that resembles an integer!
        integer dict_index = llListFindList(dict, [word]);
        if(dict_index != -1) {
            integer entry = llList2Integer(dict, dict_index + 1);
            integer immediate = llList2Integer(dict, dict_index + 2);
            if(!immediate && compiling) {
                compile_integer(entry); // compile call
            } else {
                // trace(1, "icall " + (string)entry);
                rators = [-1];        // return to interpreting after
                pc = entry;            // execute the word
                jump next4;
            }
        } else if(llSubStringIndex("0123456789", llGetSubString(word, 0, 0)) != -1) {
            integer i = (integer)word;
            if(compiling)
                compile_list([-2, i]); // literal integer
            else
                push_integer(i);
        } else {
            error(program + ":" + (string)(program_line - 1) +
                            ": Unknown word \"" + word + "\".");
            dump();
            abort();
            jump stop;
        }
    }
    
    // Ran out of words, interpret next segment.
    // Are there segments available to interpret?
    if(seg_index < llGetListLength(segs)) {
        // Is the next segment a string?
        // TODO: deal with empty string
        // TODO: deal with embedded quotes
        if(llList2String(segs, seg_index) == "\"") {
            ++seg_index;
            string seg = llList2String(segs, seg_index++);
            if(compiling)
                compile_list([-3, seg]); // literal string
            else
                push_string(seg);
            // Eat the terminating quotes, if there are any.
            // Note that if seg_index is at the ends of segs then
            // nothing happens, so a string can be terminated by
            // the end of a line.
            if(llList2String(segs, seg_index) == "\"")
                ++seg_index;
        }
        // Note that dealing with the string segment may have left
        // seg_index at the end of segs, but this is OK since the
        // result will be an empty list of words and another
        // iteration of the while loop, so there's no need to waste
        // space checking for it.
        words = llParseString2List(llList2String(segs, seg_index++),
                                   [" "],
                                   []);
        word_index = 0;
        jump next_word0;
    }

    // No segments either.    Is there a notecard to read?  If so ask
    // for the next line of the program and wait for it to arrive.
    if (program != "") {
        program_query = llGetNotecardLine(program, program_line++);
        return;
    }
    
    // No program notecard left to read, so listen for further
    // instructions.
@stop;
	running = FALSE;
    info("Ready.");
}

run_string(string s) {
    // We must keep the nulls in the string so that there can be empty strings
    // in Forth.  This can lead to empty word lists, but that does not cause
    // any real problems.
    segs = llParseStringKeepNulls(s, [], ["\""]);
    seg_index = 0;
    words = [];
    word_index = 0;
    run();
}

default {
    state_entry() {
        script = llGetScriptName();
        trace(0, "Version " + (string)version);
        script_key = llGetInventoryKey(script);
        
        // Make a list of libraries
        integer n = llGetInventoryNumber(INVENTORY_SCRIPT);
        integer l = llStringLength(lib_prefix);
        integer i;
        for(i = 0; i < n; ++i) {
            string name = llGetInventoryName(INVENTORY_SCRIPT, i);
            if(llGetSubString(name, 0, l - 1) == lib_prefix) {
                key lib_key = llGetInventoryKey(name);
                lib_scripts = (lib_scripts=[]) + lib_scripts + [lib_key, name];
            }
        }
        
        trace(1, "Found libraries " + llDumpList2String(lib_scripts, " "));

        // Request dictionary entry registration
        llMessageLinked(LINK_THIS, -2, "", script_key);
    }
    
    link_message(integer sender_num, integer num, string str, key id) {
        trace(2, "link_message(" + (string)sender_num + ", " + (string)num + ", \"" + str + "\", " + (string)id + ")");
        if(num != -3) return;
        integer lib_index = llListFindList(lib_scripts, [id]);
        if(lib_index == -1) return;
        string name = llList2String(lib_scripts, lib_index + 1);
        trace(1, "Library \"" + name + "\" registered.");
        dict = (dict=[]) + dict + llParseStringKeepNulls(str, ["|"], []);
        libs = (libs=[]) + libs + [id, name];
        if(llGetListLength(libs) == llGetListLength(lib_scripts))
            state go;
    }
}

state go {
    state_entry() {
        trace(2, "state go");

    	listen_handle = llListen(listen_channel, "", llGetOwner(), "");
		info("Listening on channel " + (string)listen_channel);

        if(llGetInventoryType(program) != INVENTORY_NOTECARD) {
            error("No program notecard called \"" + program + "\".");
            abort();
        } else
        	info("Running program from notecard \"" + program + "\".");

        run();
    }
    
    dataserver(key queryid, string data) {
        trace(2, "dataserver(" + (string)queryid + ", \"" + data + "\")");
        if(queryid != program_query) return;
        if(data == EOF) {
            program = "";
            run();
            return;
        }
        data = llStringTrim(data, STRING_TRIM);
        if(llGetSubString(data, 0, 0) == "#") { // comment
            program_query = llGetNotecardLine(program, program_line++);
            return;
        }
        run_string(data);
    }
    
    listen(integer channel, string name, key id, string message) {
        trace(2, "listen(" + (string)channel + ", \"" + name + "\", " + (string)id + ", \"" + message + "\")");
        if (channel != listen_channel && id != llGetOwner()) return;
        if (llGetSubString(message, 0, 0) == ":") { // control
        	list args = llParseString2List(message, [" "], []);
        	string command = llList2String(args, 0);
            if (command == ":reset") {
            	info("Resetting...");
            	llResetScript();
            } else if (command == ":dump") {
            	dump();
            } else if (command == ":abort") {
            	info("Aborting execution...");
            	abort();
            } else if (command == ":run") {
            	if (running)
            		error("Not ready.");
            	else {
					program = llList2String(args, 1);
					program_line = 0;
					run();
				}
            } else
                error("Unknown control command \"" + message + "\".");
            return;
        }
        if (running) {
			error("Not ready.");
			return;
		}
		info("-> " + message);
        run_string(message);
    }

    link_message(integer sender_num, integer num, string str, key id) {
        trace(2, "link_message(" + (string)sender_num + ", " + (string)num + ", \"" + str + "\", " + (string)id + ")");
        if(num != -1) return;
        rands = llParseStringKeepNulls(str, ["|"], []);
        ret();
        run();
    }
    
    touch_start(integer num_detected) {
        integer i;
        for (i = 0; i < num_detected; ++i)
            if (llDetectedKey(i) == llGetOwner())
                llDialog(llGetOwner(),
                         "Forth Interpreter v" + (string)version + "\n" +
                         "Command?",
                         [":abort", ":dump", ":reset"],
                         listen_channel);
    }
}
