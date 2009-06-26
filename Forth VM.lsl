// Forth Virtual Machine

string script;                  // Script name
key script_key;                 // This script's key
integer version = 100;          // Script version
integer debug = 3;              // Debugging level, 0 for none

list nodes = [0];               // Compiled instructions, index by "dict"
list rands;                     // Operand (parameter) stack
list rators;                    // Operator (return, linkage) stack
integer pc = -1;                // Program counter, indexes "nodes".
integer tracing = 0;            // Tracing level

// This string contains Unicode character U+E000 from the Private Use Area
// and is used to separate strings with llDumpList2String since it is very
// unlikely to be used in anything that appears in the list.
string dump_separator = "";


info(string message) {
    llOwnerSay((string)llGetLinkNumber() + " " + script + ": " + message);
}

trace(integer level, string message) {
    if(debug > level)
        info(message);
}

error(string message) {
    info("ERROR: " + message);
}


// Pack a list element previously dumped with llDumpList2String into
// a single element list using the smallest representation possible.
// Integer and float list elements occupy 20 bytes.  Singleton strings
// occupy 22 bytes.

list dumpedElement2List(string s) {
    trace(4, "dumpedElement2List(\"" + s + "\")");

    integer i = (integer)s;
    if ((i != 0 && (string)i == s) || s == (string)0) {
        trace(5, "packing \"" + s + "\" as integer");
        return [i];
    }
    
    float f = (float)s;
    if ((f != 0 && (string)f == s) || s == (string)0.0) {
        trace(5, "packing \"" + s + "\" as float");
        return [f];
    }

    // llDumpList2String converts vectors with 5 decimals but cast converts
    // them with 6 decimals, so you can't use cast to check that the string
    // is a representation of the vector.  Instead we have to put it back
    // in a list and dump it again.
    vector v = (vector)s;
    if ((v != ZERO_VECTOR &&
         llDumpList2String([v], "") == s) ||
        s == (string)ZERO_VECTOR) {
        trace(5, "packing \"" + s + "\" as vector");
        return [v];
    }
    
    // The same applies to rotations.
    rotation r = (rotation)s;
    if ((r != ZERO_ROTATION &&
         llDumpList2String([r], "") == s) ||
        s == (string)ZERO_ROTATION) {
        trace(5, "packing \"" + s + "\" as rotation");
        return [r];
    }

    trace(5, "packing \"" + s + "\" as string");
    return [s];
}

compileDumpedList(string s) {
    trace(4, "compileDumpedList(\"" + s + "\")");
    list l = llParseStringKeepNulls(s, [dump_separator], []);
    integer n = llGetListLength(l);
    integer i;
    for (i = 0; i < n; ++i)
        nodes += dumpedElement2List(llList2String(l, i));
}


// Stack Operations

push_integer(integer i) {
    rands = [i] + rands;
}

push_string(string s) {
    rands = [s] + rands;
}

push_rator(integer i) {
    rators = [i] + rators;
}

push_rator_key(key k) {
    rators = [k] + rators;
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

integer pop_rator() {
    integer i = llList2Integer(rators, 0);
    rators = llDeleteSubList(rators, 0, 0);
    return i;
}

key pop_rator_key() {
    key k = llList2Key(rators, 0);
    rators = llDeleteSubList(rators, 0, 0);
    return k;
}

ret() {
    // trace(1, "ret from pc = " + (string)pc + " rators = " + llDumpList2String(rators, " "));
    // Note: will get zero and signal an error if stack is empty.
    pc = pop_rator();
}


// Display machine state for tracing

pos(string prefix) {
    info(prefix + " " +
         llDumpList2String(rands, "|") + "||" +
         (string)pc + " " +
         llDumpList2String(rators, " "));
}


// Dump machine state

dump() {
    info("nodes = " + llDumpList2String(nodes, " "));
    info((string)llGetFreeMemory() + " bytes free");
}


abort() {
    pc = -1;
    rators = [];
}


// Operators built-in for speed
// This function is duplicated in the "Forth Library Core" script.
integer builtin(integer num) {
    if(num == -1000)        // +
        push_integer(pop_integer() + pop_integer());
    else if(num == -1001) { // -
        integer y = pop_integer();
        integer x = pop_integer();
        push_integer(x - y);
    } else if(num == -1002) // *
        push_integer(pop_integer() * pop_integer());
    else if(num == -1003) { // /
        integer y = pop_integer();
        integer x = pop_integer();
        push_integer(x / y);
    } else if(num == -1004) { // =
        string y = pop_string();
        string x = pop_string();
        push_integer(x == y);
    } else if(num == -1100) // .
        llOwnerSay(llDumpList2String(rands, " "));
    else if(num == -1200)   // drop
        pop_string();
    else if(num == -1201) { // dup
        push_string(llList2String(rands, 0));
    } else if(num == -1202) { // swap
        string y = pop_string();
        string x = pop_string();
        push_string(y);
        push_string(x);
    } else if(num == -1203) { // over
        push_string(llList2String(rands, 1));
    } else if(num == -1204) { // 2dup
        rands = (rands=[]) + llList2List(rands, 0, 1) + rands;
    } else if(num == -1205) { // pick
        integer i = pop_integer();
        push_string(llList2String(rands, i));
    } else if(num == -1206) { // rot
        integer i = pop_integer();
        integer j = pop_integer();
        integer k = pop_integer();
        push_integer(j);
        push_integer(i);
        push_integer(k);
    } else if(num == -1300) { // append
        string y = pop_string();
        string x = pop_string();
        push_string(x + y);
    } else
        return FALSE;
    return TRUE;
}


run() {
@next;
    // trace(1, "step pc = " + (string)pc + " rators = " + llDumpList2String(rators, "|") + " rands = " + llDumpList2String(rands, "|"));

    if(pc >= 0) {                // Executing compiled code?
    @next_op;
        integer op = llList2Integer(nodes, pc++);
        if(op <= 0) {            // Special in-line opcode?
            if(op == -1) {        // return
                if (tracing >= 2) pos("ret");
                ret();
                jump next;
            }
            if(op == -5) {      // tail call
                pc = llList2Integer(nodes, pc++);
                if (tracing >= 1) pos("tail");
                jump next;
            }
            if(op == -2) {        // literal integer
                push_integer(llList2Integer(nodes, pc++));
                jump next_op;
            }
            if(op == -3) {        // literal string
                push_string(llList2String(nodes, pc++));
                jump next_op;
            }
            if(op == -4) {       // rator to rand
                // Technically this is possible out-of-line but it involves
                // more list operations.
                push_integer(pop_rator());
                jump next_op;
            }
            if(op == 0) {       // return from empty stack etc.
                error("Zero operator fault.");
                dump();
                abort();
                // Could encode diagnostic information in string.
                llMessageLinked(LINK_THIS, 0x51a20012, "", script_key);
                return;
            }
            // Fall through if unrecognized negative op.
        }
        // Call the operator
        // trace(1, "call " + (string)op);
        push_rator(pc);
        pc = op;
        if (tracing >= 1) pos("call");
        jump next;
    }
    
    if(pc == -1) {  // return from VM
        // Send a return result message to the calling script.
        llMessageLinked(LINK_THIS,
                        0x51a20011,
                        llDumpList2String(rands, dump_separator),
                        pop_rator_key());
        return;
    } else if(pc == -71) {  // "!", call block
        // Replace the current PC with the stack top and do _not_ return.
        // i.e. tail call the stack top
        pc = pop_integer();
    } else if (pc == -80) { // "if"
        integer f = pop_integer();
        integer t = pop_integer();
        integer b = pop_integer();
        if (b)
            pc = t;
        else
            pc = f;
        // Tail call
    } else if (builtin(pc)) {
        ret();
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


default {
    state_entry() {
        script = llGetScriptName();
        trace(0, "Version " + (string)version);
        script_key = llGetInventoryKey(script);
    }
    
    link_message(integer sender_num, integer num, string str, key id) {
        trace(2, "link_message(" + (string)sender_num + ", " + (string)num + ", \"" + str + "\", " + (string)id + ")");
        // TODO: Reorder common codes to the top.
        if (num == 0x51A20001) {        // compile
            compileDumpedList(str);
        } else if (num == 0x51a20010) { // run
            // Push the key of the calling script so we can send the return
            // message back to it.
            push_rator_key(id);
            // Push the return operator so that returning from the call sends
            // the return message.
            push_rator(-1);
            rands = llParseStringKeepNulls(str, [dump_separator], []);
            pc = pop_integer();
            run();
        } else if (num == 0x51a20011 && id == script_key) { // return to me
            rands = llParseStringKeepNulls(str, [dump_separator], []);
            ret();
            run();        
        } else if (num == 0x51a20020) { // dump
            dump();
        }
    }
}
