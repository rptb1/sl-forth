// Forth Library Core
//
// Copyright 2008 Richard Brooksby
//
// Provides basic operations to the Forth Interpreter.  In here should go everything which
// is general purpose but which doesn't need access to the internals.

string script;                  // Script name
key script_key;                 // This script's key 
integer version = 202;          // Script version
integer debug = 1;              // Debugging level, 0 for none

list rands;                     // Operand stack

list dict = [
    "+", -1000, FALSE,
    "-", -1001, FALSE,
    "*", -1002, FALSE,
    "/", -1003, FALSE,
    "=", -1004, FALSE,
    ".", -1100, FALSE,
    "drop", -1200, FALSE,
    "dup", -1201, FALSE,
    "swap", -1202, FALSE,
    "over", -1203, FALSE,
    "2dup", -1204, FALSE,
    "pick", -1205, FALSE,
    "append", -1300, FALSE
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

print_stack() {
    llOwnerSay(llDumpList2String(rands, " "));
}

default {
    state_entry() {
        script = llGetScriptName();
        trace(0, "Version " + (string)version);
        script_key = llGetInventoryKey(script);
    }

    link_message(integer sender_num, integer num, string str, key id) {
        trace(2, "link_message(" + (string)sender_num + ", " + (string)num + ", \"" + str + "\", " + (string)id + ")");
        if(num == -2) {         // Dictionary registration
            llMessageLinked(LINK_THIS, -3, llDumpList2String(dict, "|"), script_key);
            return;
        }
        // Unpack the operand stack.
        rands = llParseStringKeepNulls(str, ["|"], []);

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
            print_stack();
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
        } else if(num == -1300) { // append
            string y = pop_string();
            string x = pop_string();
            push_string(x + y);
        } else
            return;             // Unrecognized -- ignore
            
        // Send back the results
        llMessageLinked(sender_num, -1, llDumpList2String(rands, "|"), script_key);
    }
}
