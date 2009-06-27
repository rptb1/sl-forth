// Forth Library Core
//
// Copyright 2008 Richard Brooksby
//
// Provides basic operations to the Forth Interpreter.  In here should go everything which
// is general purpose but which doesn't need access to the internals.
//
// http://www.firmworks.com/QuickRef.html

string script;                  // Script name
key script_key;                 // This script's key 
integer version = 208;          // Script version
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
    "-rot", -1207,
    "nip", -1208,
    "tuck", -1209,
    "roll", -1210,
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
    if(num == -1000) {      // +
        rands = llListReplaceList(
            rands,
            [llList2Integer(rands, 0) + llList2Integer(rands, 1)],
            0, 1
        );
    } else if(num == -1001) { // -
        rands = llListReplaceList(
            rands,
            [llList2Integer(rands, 1) - llList2Integer(rands, 0)],
            0, 1
        );
    } else if(num == -1002) { // *
        rands = llListReplaceList(
            rands,
            [llList2Integer(rands, 0) * llList2Integer(rands, 1)],
            0, 1
        );
    } else if(num == -1003) { // /
        rands = llListReplaceList(
            rands,
            [llList2Integer(rands, 1) / llList2Integer(rands, 0)],
            0, 1
        );
    } else if(num == -1004) { // =
        rands = llListReplaceList(
            rands,
            [llList2String(rands, 0) == llList2String(rands, 1)],
            0, 1
        );
    } else if(num == -1100) { // .
        llOwnerSay(llDumpList2String(rands, " "));
    } else if(num == -1200) { // drop
        rands = llDeleteSubList(rands, 0, 0);
    } else if(num == -1201) { // dup
        rands = llListInsertList(rands, llList2List(rands, 0, 0), 0);
    } else if(num == -1202) { // swap
        rands = llListReplaceList(
            rands,
            llList2List(rands, 1, 1) + llList2List(rands, 0, 0),
            0, 1
        );
    } else if(num == -1203) { // over
        rands = llListInsertList(rands, llList2List(rands, 1, 1), 0);
    } else if(num == -1204) { // 2dup
        rands = llListInsertList(rands, llList2List(rands, 0, 1), 0);
    } else if(num == -1205) { // pick
        integer i = pop_integer();
        rands = llListInsertList(rands, llList2List(rands, i, i), 0);
    } else if(num == -1206) { // rot
        rands = llListReplaceList(
            rands,
            llList2List(rands, 2, 2) + llList2List(rands, 0, 1),
            0, 2
        );
    } else if(num == -1300) { // append
        rands = llListInsertList(
            rands,
            [llList2String(rands, 1) + llList2String(rands, 0)],
            0
        );
    } else if (num == -1207) { // -rot
        rands = llListReplaceList(
            rands,
            llList2List(rands, 1, 2) + llList2List(rands, 0, 0),
            0, 2
        );
    } else if (num == -1208) { // nip
        rands = llDeleteSubList(rands, 1, 1);
    } else if (num == -1209) { // tuck
        rands = llListInsertList(
            rands,
            llList2List(rands, 0, 0),
            2
        );
    } else if (num == -1210) { // roll
        integer i = pop_integer();
        rands = llListReplaceList(
            rands,
            llList2List(rands, i, i) + llList2List(rands, 0, i - 1),
            0, i
        );
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
