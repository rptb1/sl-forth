// Forth Library Pack
//
// Copyright 2008 Richard Brooksby

string script;                  // Script name
key script_key;                 // This script's key 
integer version = 107;          // Script version
integer debug = 1;              // Debugging level, 0 for none

float timeout = 5.0;            // How long to wait for a response

integer box_channel = 29842;

integer sender;
key box;
string item;
integer action;

list actions;                   // Actions pending acknowledgements

list rands;                     // Operand stack

list dict = [
    "pack:box", -2000, FALSE,
    "pack:name", -2001, FALSE,
    "pack:texture", -2002, FALSE,
    "pack:description", -2003, FALSE,
    "pack:add", -2004, FALSE,
    "pack:done", -2005, FALSE
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

push_key(key k) {
    rands = (rands=[]) + [k] + rands;
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

key pop_key() {
    key k = llList2Key(rands, 0);
    rands = llDeleteSubList(rands, 0, 0);
    return k;
}

enter(integer sender_num, integer num, string str) {
    rands = llParseStringKeepNulls(str, ["|"], []);
    sender = sender_num;
    action = num;
}

ret() {
    llMessageLinked(sender, -1, llDumpList2String(rands, "|"), script_key);
}

add_action(string command, key box, string item) {
    trace(3, "Adding command " + command + " of \"" + item + "\" to box " + (string)box + ".");
    if (llGetListLength(actions) == 0)
        llSetTimerEvent(timeout);
    actions = (actions=[]) + actions + [command, box, item, llGetTime()];
}

print_stack() {
    llOwnerSay(llDumpList2String(rands, " "));
}

default {
    state_entry() {
        script = llGetScriptName();
        trace(0, "Version " + (string)version);
        script_key = llGetInventoryKey(script);
        llListen(box_channel + 1, "", NULL_KEY, "");
    }

    link_message(integer sender_num, integer num, string str, key id) {
        trace(2, "link_message(" + (string)sender_num + ", " + (string)num + ", \"" + str + "\", " + (string)id + ")");
        if(num == -2) {         // Dictionary registration
            llMessageLinked(LINK_THIS, -3, llDumpList2String(dict, "|"), script_key);
            llResetScript();
        }

        if(num == -2000) {       // box
            enter(sender_num, num, str);
            string name = pop_string();
            llRezObject(name, llGetPos(), ZERO_VECTOR, llGetRot(), box_channel);
            llSetPos(llGetPos() + llRot2Up(llGetRot()) * 0.5);
            return;             // wait for rez
        } else if(num == -2001) { // name
            enter(sender_num, num, str);
            string name = pop_string();
            key box = pop_key();
            llSay(box_channel, (string)box + "|name|" + name);
        } else if(num == -2002) { // texture
            enter(sender_num, num, str);
            item = pop_string();
            box = pop_key();
            llMessageLinked(LINK_SET, 2002, item, box);
            add_action("texture", box, item);
        } else if(num == -2003) { // description
            enter(sender_num, num, str);
            string desc = pop_string();
            key box = pop_key();
            llSay(box_channel, (string)box + "|description|" + desc);
            // @@@@ Need to deal with acknowledgement
        } else if(num == -2004) { // add
            enter(sender_num, num, str);
            item = pop_string();
            box = pop_key();
            llMessageLinked(LINK_SET, 2001, item, box);
            add_action("add", box, item);
        } else if(num == -2005) { // done
            enter(sender_num, num, str);
            key box = pop_key();
            llSay(box_channel, (string)box + "|done");
        } else
            return;             // Unrecognized -- ignore
            
        // Send back the results
        ret();
    }

    listen(integer channel, string name, key id, string message) {
        trace(2, "listen(" + (string)channel + ", \"" + name + "\", " + (string)id + ", \"" + message + "\")");
        if (channel != box_channel + 1) return;
        if (id != box) return;
        trace(3, "Actions: " + llDumpList2String(actions, ", "));
        list fields = llParseStringKeepNulls(message, ["|"], []);
        string command = llList2String(fields, 1);
        string item = llList2String(fields, 2);
        integer index;
        trace(3, "Command " + command + " id " + (string)id + " item " + item);
        if (command != "texture")
            index = llListFindList(actions, [command, id, item]);
        else // box sends back texture key, not name, sadly!
            index = llListFindList(actions, [command, id]);
        if (index != -1) {
            trace(2, "Received acknowledgement for " + command + " of " + item + " to box " + (string)id);
            actions = llDeleteSubList(actions, index, index + 3);
            if (llGetListLength(actions) == 0)
                llSetTimerEvent(0.0);
        } else
            trace(2, "Ignoring unknown message \"" + message + "\" from box " + (string)id);
    }
    
    timer() {
        trace(2, "timer()");
        integer i = 0;
        trace(3, "Actions: " + llDumpList2String(actions, ", "));
        while (i < llGetListLength(actions)) {
            string command = llList2String(actions, i);
            key box = llList2String(actions, i + 1);
            string item = llList2String(actions, i + 2);
            float t = llList2Float(actions, i + 3);
            trace(3, "Checking action " + (string)(i / 4) +
                      ": " + command + " \"" + item + "\" to box " +(string)box +
                      " from " + (string)(llGetTime() - t) + " ago.");
            if (llGetTime() - t >= timeout) {
                llOwnerSay("ERROR: Failed to " + command + " \"" + item + "\" to box " + (string)box + ".");
                actions = llDeleteSubList(actions, i, i + 3);
            } else
                i += 4;
        }
        if (llGetListLength(actions) == 0)
            llSetTimerEvent(0.0);
    }

    object_rez(key id) {
        trace(2, "object_rez(" + (string)id + ")");
        push_string((string)id);
        ret();
    }
}
