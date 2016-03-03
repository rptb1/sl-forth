===================
Fix for Second Life
===================

:Author: Richard Brooksby
:Date: 2009-06

A higher order scripting language for Second Life.


The Problem
-----------

In LSL you can't write simple things like::

    x = rez("box");
    give(x, "thing");
    give(x, "another thing");

and no, you can't do it with functions either.  It is because LSL
demands that you return from an event handler in order to get another
event.  This makes some very simple things very difficult.  It forces
you to store lots of state in global variables.  It prevents you writing
higher-order things at all!

Fix is a simple language interpreter/compiler written in LSL which lets
you write some kinds of programs much more easily.  It is will not help
solve every problem, and it not suitable for every task, but it can help
a great deal with automation.  Using it can save you a lot of effort.

Fix is a `concatenative programming language`_ , like PostScript™ or
Forth.  It was chosen because it is possible to parse, interpret, and
compile such languages quickly with small amounts of code.  It is
therefore suitable for implementation in LSL, which has very limited
resources.

.. _`concatenative programming language`: http://en.wikipedia.org/wiki/Concatenative_programming_language

However, it will take a little getting used to.

A Fix program is a simple sequence of atoms, separated by white space. 
An atom is either:

  - an integer  0, 1, 2, -4
  - a string    "hello"
  - a word      foo

That's it.  Atoms are interpreted from left to right, top to bottom, in
order.  The most important words are:

    {
        starts compilation

    }
        stop compilation

    ;
        defines a word

Here is an example::

    "foo" {
      ", world" append
    } ;

This defines a word "foo" which appends the string ", world" to whatever
is on top of the stack.  If we run it we get::

    "hello" foo print


Extending Fix
-------------

Fix has only a tiny number of built-in words.  This is to keep the
interpreter/compiler very small and as keep as much memory as possible
available for actual programs.  Most words are defined in separate LSL
scripts called "Fix Libraries".

A Fix library is a script which responds to link messages from the Fix
interpreter in order to execute words.  It also responds to some special
link messages in order to register those words in the Fix dictionary so
that they can be called from Fix programs.

Each Fix library has a dictionary which looks like this::

    list dict = [
        "+", -1000, FALSE,
        "-", -1001, FALSE,
        "*", -1002, FALSE,
        "/", -1003, FALSE
    ];

[This is as far as the manual went.  Sorry about that.  RB 2016-03-03]
