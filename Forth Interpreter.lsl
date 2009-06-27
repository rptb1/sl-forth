// Forth Interpreter
//
// Copyright 2008 Richard Brooksby
// Written on the evening of 2008-01-14.

string script;                  // Script name
key script_key;                 // This script's key
integer version = 601;          // Script version
integer debug = 2;              // Debugging level, 0 for none

// This string contains Unicode character U+E000 from the Private Use Area
// and is used to separate strings with llDumpList2String since it is very
// unlikely to be used in anything that appears in the list.
string dump_separator = "";

string program = "Forth Program"; // Program notecard name or empty for none.
integer listen_period = 0;      // How long to listen after a touch.
integer listen_channel = 3;     // Channel to listen for commands

string lib_prefix = "Forth Library "; // Library script name prefix
list lib_scripts;               // Potential library scripts
list libs;                      // Registered library scripts

string config;                  // Configuration notecard name
key config_query;               // Pending configuration query or NULL_KEY when done
integer config_line;            // Next configuration notecard line to read

integer program_line;           // Next line to read from notecard
key program_query;              // Dataserver query for reading line
list segs;                      // String/non-string segments
integer seg_index;              // Index of next segment to process
list words;                     // Words
integer word_index;             // Index of next word to process
list nodes= [];                 // Compiled instructions to be sent to VM later
integer there = 1;              // Index of first compiled node
integer here = 1;               // Index of next compiled node
list rands;                     // Operand (parameter) stack
list rators;                    // Operator (return, linkage) stack
integer pc = -1;                // Program counter, indexes "nodes".
integer compiling;              // Are we compiling or executing?
integer running;                // Are we running?
integer listen_handle = 0;      // Listen handle for further commands
integer last_op;                // Last compiled operator or -1
integer tracing = 0;            // Tracing level

// Nucleus dictionary
// It's possible to make a more primitive nucleus with things like
// "HERE", "'", ",", etc. in it and define things in terms of that
// but that's not really the use of this interpreter.
list dict = [
    "{", -50,                   // Start block
    "}", -51,                   // End block
    ";", -70,                   // Define word
    "!", -71,                   // Call block
    "recursive", -72,           // Fixed point operator
    "if", -80
];

info(string message) {
    llOwnerSay((string)llGetLinkNumber() + " " + script + ": " + message);
}

error(string message) {
    info("ERROR: " + message);
}

compilation_error(string message) {
    if(program != "")
        error(program + ":" + (string)(program_line - 1) +
                        ": " + message);
    else
        error(message);
}

trace(integer level, string message) {
    if(debug > level)
        info(message);
}

pos(string prefix) {
    integer dict_index = llListFindList(dict, [pc]);
    string word = "?";
    if (dict_index != -1)
        word = llList2String(dict, dict_index - 1);
    info(prefix + " " +
         llDumpList2String(rands, "|") + "||" +
         word + " " + (string)pc + " " +
         llDumpList2String(rators, " "));
}

integer is_integer(string s) {
    integer i = (integer)s;
    return (i != 0 && s == (string)i) || s == "0";
}

push_integer(integer i) {
    rands = [i] + rands;
}

push_string(string s) {
    rands = [s] + rands;
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

push_rator(integer i) {
    rators = [i] + rators;
}

integer pop_rator() {
    integer i = llList2Integer(rators, 0);
    rators = llDeleteSubList(rators, 0, 0);
    return i;
}

ret() {
    // trace(1, "ret from pc = " + (string)pc + " rators = " + llDumpList2String(rators, " "));
    // Note: will get zero and signal an error if stack is empty.
    pc = pop_rator();
}

compile_op(integer i) {
    nodes += [i];
    ++here;
    // If it's a call then remember it so that we can optimise tail calls.
    // We're allowed to tail to the nucleus dictionary too, so things like
    // "if" and "!" can be tailed-to.
    if (i > 0 || i <= -50) last_op = i;
}

compile_preop(integer i) {
    nodes = llListInsertList(nodes, [i], llGetListLength(nodes) - 1);
    ++here;
    // We don't know what the last op is anymore.
    last_op = -1;
}

compile_opover(integer a, integer i) {
    integer index = a - there;
    nodes = llListReplaceList(nodes, [i], index, index);
}

compile_list(list l) {
    nodes += l;
    here += llGetListLength(l);
    // This is used for literals so we can't optimise tails.
    last_op = -1;
}

compile_send() {
    llMessageLinked(LINK_THIS,
                    0x51A20001,
                    llDumpList2String(nodes, dump_separator),
                    script_key);
    nodes = [];
    there = here;
}


// dump -- dump virtual machine state

dump() {
    info("pc = " + (string)pc);
    info("rands = " + llDumpList2String(rands, "|"));
    info("rators = " + llDumpList2String(rators, "|"));
    info("words = " + llDumpList2String(words, " "));
    info("word index = " + (string)word_index);
    info("segs = " + llDumpList2String(segs, "|"));
    info("seg index = " + (string)seg_index);
    info("program = " + program);
    info("program line = " + (string)program_line);
    info("dict = " + llDumpList2String(dict, " "));
    info("here = " + (string)here);
    info("compiling = " + (string)compiling);
    info((string)llGetFreeMemory() + " bytes free");
    llMessageLinked(LINK_THIS, 0x51a20020, "", script_key);
    // TODO: Could provide a backtrace by looking up the rators in the
    // dictionary.
}


// abort -- stop execution
//
// Clears the virtual machine state so that the machine will do nothing if run
// except wait for new input.

abort() {
    segs = [];
    seg_index = 0;
    words = [];
    word_index = 0;
    program = "";
    pc = -1;
    compiling = FALSE;
}


// run -- run the virtual machine until it requires an external event
//
// The external events that can cause execution to suspend are:
//   - external call to library, which waits for a link message
//      (see the link_message hander)
//   - request the next line from the program notecard
//     (see the dataserver handler)
//   - waiting for next interactive line from the chat channel
//     (see the listen handler)
// Run-time errors cause the machine to abort and wait for interactive input.

run() {
    running = TRUE;

@next;
    // trace(1, "step pc = " + (string)pc + " rators = " + llDumpList2String(rators, "|"));

    if(pc >= 0) {                // Executing compiled code?
        // Ask the VM to execute
        push_integer(pc);
        llMessageLinked(LINK_THIS,
                        0x51a20010,
                        llDumpList2String(rands, dump_separator),
                        script_key);
        // Wait for a reply from the VM
        return;
    }

    // If pc is -1 then we are returning to the interpreter after making
    // an immediate call from the compiler.

    if(pc != -1) {                // Built-in or external function
        if(pc == -70) {            // ";", define word
            integer entry = pop_integer();
            string word = pop_string();
            // Must forbid words that resemble integers to prevent dictionary
            // search foul-ups, since there is no strided list search.
            if(is_integer(word)) {
                compilation_error("Word may not resemble a number.");
                abort();
                jump stop;
            }
            trace(1, "Defining word \"" + word + "\".");
            dict += [word, entry];
            ret();
        } else if(pc == -50) {  // "{", start block
            push_integer(here);
            if (compiling)
                compile_op(0);     // placeholder for call over block
            push_integer(compiling);
            compiling = TRUE;
            last_op = -1;       // No last operator yet!
            ret();
        } else if(pc == -51) {  // "}", end block
            if (!compiling) {
                compilation_error("End of block when not compiling.");
                abort();
                jump stop;
            }
            if (last_op != -1) {  // tail call possible?
                // Insert a tail operator before the last op.
                compile_preop(-5);
            } else {
                // Append a ret op to the block contents
                compile_op(-1);
            }
            // Retrieve the start of the block and the previous
            // compilation state.
            compiling = pop_integer();
            integer index = pop_integer();
            if (compiling) {
                // Replace the placeholder before the block with a call to
                // here followed by a R> operation, so that the block entry
                // point ends up on the stack at run-time.
                compile_opover(index, here);
                compile_op(-4);
            } else {
                // Just push the entry point.
                push_integer(index);
                compile_send();
            }
            ret();
        } else if(pc == -71) {  // "!", call block
            // Replace the current PC with the stack top and do _not_ return.
            // i.e. tail call the stack top
            pc = pop_integer();
        } else if (pc == -72) { // "recursive" fixed point operator
            // Compile a new operator which, when called, pushes itself onto
            // the stack and tails to its argument, and is thus the fixed
            // point of its argument.
            integer index = here;
            compile_list([-2, index,
                          -5, pop_integer()]);
            push_integer(index);
            ret();
        } else if (pc == -80) { // "if"
            integer f = pop_integer();
            integer t = pop_integer();
            integer b = pop_integer();
            if (b)
                pc = t;
            else
                pc = f;
            // Tail call
        } else {
            // External call
            // trace(1, "ecall pc = " + (string)pc + " rators = " + llDumpList2String(rators, " "));
            llMessageLinked(LINK_THIS,
                            pc,
                            llDumpList2String(rands, dump_separator),
                            script_key);
            return;                    // Wait for reply
        }
        jump next;
    }

@next_word;

    // Interpret words until they are exhausted.
    integer word_count = llGetListLength(words);
    while(word_index < word_count) {
        string word = llList2String(words, word_index++);
        if (is_integer(word)) {
            integer i = (integer)word;
            if(compiling)
                compile_list([-2, i]); // literal integer
            else
                push_integer(i);
        } else {
            // Since there is only one string column in dict this won't
            // accidentally find the wrong things.  Words are checked so that
            // they can't resemble integers.
            integer dict_index = llListFindList(dict, [word]);
            if(dict_index != -1) {
                integer entry = llList2Integer(dict, dict_index + 1);
                integer immediate = -70 < entry && entry <= -50;
                if(!immediate && compiling) {
                    compile_op(entry); // compile call
                } else {
                    // trace(1, "icall " + (string)entry);
                    rators = [-1];        // return to interpreting after
                    pc = entry;            // execute the word
                    jump next;
                }
            } else {
                compilation_error("Unknown word \"" + word + "\".");
                // dump();
                abort();
                jump stop;
            }
        }
    }

    // Ran out of words, interpret next segment.
    // Are there segments available to interpret?
    if(seg_index < llGetListLength(segs)) {
        // Is the next segment a string?
        // TODO: deal with embedded quotes
        if(llList2String(segs, seg_index) == "\"") {
            ++seg_index;
            string seg = llList2String(segs, seg_index++);
            if(seg == "\"") {       // empty string
                seg = "";
                --seg_index;
            }
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
        words = llParseString2List(llList2String(segs, seg_index++), [" "], []);
        word_index = 0;
        jump next_word;
    }

    // No segments either.  Is there a notecard to read?  If so ask
    // for the next line of the program and wait for it to arrive.
    if (program != "") {
        program_query = llGetNotecardLine(program, program_line++);
        return;
    }

    // No program notecard left to read, so listen for further
    // instructions.
@stop;
    running = FALSE;
    info("Ready.  " + (string)llGetFreeMemory() + " bytes free.");
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

integer setup_done() {
    return config_query == NULL_KEY &&
           llGetListLength(libs) == llGetListLength(lib_scripts);
}

listen_timeout() {
    if (listen_period > 0) {
        llSetTimerEvent(listen_period);
        info("Listening on channel " + (string)listen_channel +
              " for " + (string)listen_period + " seconds.");
    } else
        info("Listening on channel " + (string)listen_channel + ".");
}

default {
    state_entry() {
        script = llGetScriptName();
        trace(0, "Version " + (string)version);
        script_key = llGetInventoryKey(script);

        // Read the configuration notecard if there is one to override
        // any of the settings.
        config = script + " config";
        if(llGetInventoryType(config) == INVENTORY_NOTECARD) {
            trace(1, "Reading from notecard \"" + config + "\".");
            config_query = llGetNotecardLine(config, config_line++);
        }

        // TODO: Should transition to new state here only when configuration
        // is complete, so that config can change things like lib_prefix.

        // Make a list of libraries
        integer n = llGetInventoryNumber(INVENTORY_SCRIPT);
        integer l = llStringLength(lib_prefix);
        integer i;
        for(i = 0; i < n; ++i) {
            string name = llGetInventoryName(INVENTORY_SCRIPT, i);
            if(llGetSubString(name, 0, l - 1) == lib_prefix) {
                key lib_key = llGetInventoryKey(name);
                lib_scripts += [lib_key, name];
            }
        }

        trace(1, "Found libraries " + llDumpList2String(lib_scripts, " "));

        // Request dictionary entry registration
        llMessageLinked(LINK_THIS, 0x51a20030, "", script_key);
    }

    link_message(integer sender_num, integer num, string str, key id) {
        trace(2, "link_message(" + (string)sender_num + ", " + (string)num + ", \"" + str + "\", " + (string)id + ")");
        if (num == 0x51a20031) {
            integer lib_index = llListFindList(lib_scripts, [id]);
            if(lib_index == -1) return;
            string name = llList2String(lib_scripts, lib_index + 1);
            trace(1, "Library \"" + name + "\" registered.");
            dict += llParseStringKeepNulls(str, [dump_separator], []);
            libs += [id, name];
            if (setup_done()) state go;
        }
    }

    // This is just used for getting the information from the config notecard.
    // Programs are run from notecards in the "running" state.
    dataserver(key query, string data) {
        trace(2, "dataserver(" + (string)query + ", \"" + data + "\")");
        if (query != config_query) {
            trace(3, "Ignoring unexpected dataserver response " + (string)query);
            return;
        }
        if(data == EOF) {
            config_query = NULL_KEY;
            if (setup_done()) state go;
            return;
        }
        config_query = llGetNotecardLine(config, config_line++);
        data = llStringTrim(data, STRING_TRIM);
        if(llGetSubString(data, 0, 0) == "#") return; // comment
        integer index = llSubStringIndex(data, "=");
        if(index < 1) return;
        string var = llStringTrim(llGetSubString(data, 0, index - 1), STRING_TRIM_TAIL);
        string val = llStringTrim(llGetSubString(data, index + 1, -1), STRING_TRIM_HEAD);
        trace(3, "var = \"" + var + "\" val = \"" + val + "\"");
        if (var == "" || val == "") return;
        if (var == "program")
            program = val;
        else if (var == "debug")
            debug = (integer)val;
        else if (var == "listen_channel")
            listen_channel = (integer)val;
        else if (var == "listen_period")
            listen_period = (integer)val;
        else
            llOwnerSay("Ignoring unknown setting for \"" + var + "\".");
    }
}

state go {
    state_entry() {
        trace(2, "state go");

        if (listen_channel >= 0) {
            listen_handle = llListen(listen_channel, "", llGetOwner(), "");
            listen_timeout();
        }

        if(llGetInventoryType(program) != INVENTORY_NOTECARD) {
            error("No program notecard called \"" + program + "\".");
            abort();
        } else
            info("Running program from notecard \"" + program + "\".");

        run();
    }

    touch_start(integer num_detected) {
        if (listen_handle != 0) {
            integer i;
            for (i = 0; i < num_detected; ++i)
                if (llDetectedKey(i) == llGetOwner()) {
                    llListenControl(listen_handle, TRUE);
                    listen_timeout();
                }
        }
    }

    timer() {
        llSetTimerEvent(0);
        llListenControl(listen_handle, FALSE);
    }

    dataserver(key queryid, string data) {
        trace(2, "dataserver(" + (string)queryid + ", \"" + data + "\")");
        if(queryid != program_query) return;
        if(data == EOF) {
            program = "";
            run(); // TODO: Is this necessary?
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
        trace(2, "listen(" + (string)channel + ", \"" + name + "\", " +
                 (string)id + ", \"" + message + "\")");
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
                    info("Running notecard \"" + program + "\".");
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
        trace(2, "link_message(" + (string)sender_num + ", " +
                 (string)num + ", \"" + str + "\", " + (string)id + ")");
        if (num == 0x51a20011 && id == script_key) { // return to me
            rands = llParseStringKeepNulls(str, [dump_separator], []);
            ret();
            run();
        } else if (num == 0x51a20012) { // VM fault
            abort();
            // TODO: Not sure what to do next!
        }
    }
}
