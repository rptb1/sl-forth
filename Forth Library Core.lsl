// Forth Library Core
//
// Copyright 2008 Richard Brooksby
//
// Provides basic operations to the Forth Interpreter.  In here should go everything which
// is general purpose but which doesn't need access to the internals.

string script;                  // Script name
key script_key;                 // This script's key 
integer version = 207;          // Script version
integer debug = 1;              // Debugging level, 0 for none

// This string contains Unicode character U+E000 from the Private Use Area
// and is used to separate strings with llDumpList2String since it is very
// unlikely to be used in anything that appears in the list.
string dump_separator = "";

list rands;                     // Operand stack

list dict = [
    "+", -1000,
    "-", -1001,
    "*", -1002,
    "/", -1003,
    "=", -1004,
    ".", -1100,
    "drop", -1200,
    "dup", -1201,
    "swap", -1202,
    "over", -1203,
    "2dup", -1204,
    "pick", -1205,
    "rot", -1206,
    "append", -1300
];

trace(integer level, string message) {
    if(debug > level)
        llOwnerSay((string)llGetLinkNumber() + " " + script + ": " + message);
}

push_integer(integer i) {
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

// This function is duplicated in the "Forth VM" script.
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


default {
    state_entry() {
        script = llGetScriptName();
        trace(0, "Version " + (string)version);
        script_key = llGetInventoryKey(script);
    }

    link_message(integer sender_num, integer num, string str, key id) {
        trace(2, "link_message(" + (string)sender_num + ", " + (string)num + ", \"" + str + "\", " + (string)id + ")");

        if(num == 0x51a20030) {         // Dictionary registration
            llMessageLinked(LINK_THIS,
                            0x51a20031,
                            llDumpList2String(dict, dump_separator),
                            script_key);
            return;
        }

        // Unpack the operand stack.
        rands = llParseStringKeepNulls(str, [dump_separator], []);
        
        if (builtin(num))
            llMessageLinked(sender_num,
                            0x51a20011,
                            llDumpList2String(rands, dump_separator),
                            id);
    }
}
