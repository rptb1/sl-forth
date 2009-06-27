// Fix Interpreter and Compiler


// General Script

string script;                  // Script name
key script_key;                 // This script's key
integer version = 100;          // Script version
integer debug = 2;              // Debugging level, 0 for none

// Constants

string DUMP_SEPARATOR = "";    // U+E000 private use for dumping lists

// Nucleus dictionary
list dict = [
    "{", -50,                   // Start block
    "}", -51,                   // End block
    ";", -70,                   // Define word
    "!", -71,                   // Call block
    "recursive", -72,           // Fixed point operator
    "if", -80
];


// Debugging output

info(string message) {
    llOwnerSay((string)llGetLinkNumber() + " " + script + ": " + message);
}

trace(integer level, string message) {
    if(debug > level)
        info(message);
}


// Compiling to nodes
// The various "compile" functions collect opcodes in the nodes list until
// compile_send() is called, when they are sent to the virtual machine.

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
                llMessageLinked(LINK_THIS,
                                0x51a21011,
                                "Word may not resemble a number.",
                                caller);
                abort();
                return;
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
                llMessageLinked(LINK_THIS,
                                0x51a21012,
                                "End of block when not compiling.",
                                caller);
                abort();
                return;
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
                llMessageLinked(LINK_THIS,
                                0x51a21010,
                                "Unknown word \"" + word + "\".",
                                caller);
                abort();
                return;
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
    
    // No segments either.  The interpreter is ready for new instructions.
    llMessageLinked(LINK_THIS, 0x51a20031, "", caller);
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



// Test whether a string represents an integer.
// NOTE: This doesn't accept integers with leading zeros, including "00" etc.
// but probably should.
integer is_integer(string s) {
    integer i = (integer)s;
    return (i != 0 && s == (string)i) || s == "0";
}

default {
}


