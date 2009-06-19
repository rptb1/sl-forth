// Forth Library Vector
//
// Copyright 2008 Richard Brooksby

string script;                  // Script name
key script_key;                 // This script's key 
integer version = 100;          // Script version
integer debug = 1;              // Debugging level, 0 for none

list rands;                     // Operand stack

list dict = [
    "vector:make", -3000, FALSE,
    "vector:xyz", -3001, FALSE
];

trace(integer level, string message) {
    if(debug > level)
        llOwnerSay((string)llGetLinkNumber() + " " + script + ": " + message);
}

push_integer(integer i) {
    rands = [i] + rands;
}

push_string(string s) {
    rands = [s] + rands;
}

push_vector(vector v) {
    rands = [v] + rands;
}

integer pop_integer() {
    integer i = llList2Integer(rands, 0);
    rands = llDeleteSubList(rands, 0, 0);
    return i;
}

integer pop_float() {
    float f = llList2Float(rands, 0);
    rands = llDeleteSubList(rands, 0, 0);
    return f;
}

string pop_string() {
    string s = llList2String(rands, 0);
    rands = llDeleteSubList(rands, 0, 0);
    return s;
}

vector pop_vector() {
    vector v = llList2Vector(rands, 0);
    

print_stack() {
    llOwnerSay(llDumpList2String(rands, " "));
    rands = llDeleteSubList(rands, 0, 0);
    return v;
}

ret() {
    // Send back the results
    llMessageLinked(sender_num, -1, llDumpList2String(rands, "|"), script_key);
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

        if (num == -3000) {
           float x = pop_float();
           float y = pop_float();
           float z = pop_float();
           push_vector(<x, y, z>);
           ret();
        } if (num == -3001) {
           vector v = pop_vector();
           push_float(v.z);
           push_float(v.y);
           push_float(v.x);
           ret();
        }  
    }
}
