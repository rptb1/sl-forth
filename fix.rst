Fix
===
:author: Richard Brooksby
:date: 2008-01-20
:copyright: © 2008 Richard Brooksby

(Originally published at <http://chard.livejournal.com/56744.html>.)

I recently had occasion to write a Forth interpreter in Linden Scripting
Language (in Second Life). I've done it before (more than twice) and it
only took me an hour or two. I've written the odd Scheme interpreter
(and compiler) too. Forth and Scheme are both elegant little things, and
I've always wanted to think of a way of combining them, but with the aim
of making Scheme smaller and simpler, but making Forth a bit more
workable.

Well, I've come up with something that's smaller than either, but may
not be at all workable.

This is somewhat stream-of-consciousness language design. If you think
this is somewhat rambling and random you should have seen what I edited
it down from. I'm not claiming that this is brilliant stuff — it's just
something that caused me a brainstorm and that I've enjoyed thinking
about. I'm posting it in case other people might enjoy it, and who
knows, it might be useful for something. But it's probably an
`esolang <http://en.wikipedia.org/wiki/Esoteric_programming_language>`__.

For the sake of this article I'm calling my language "Fix".

One of the big advantages of a Forth interpreter is that there is no
need for recursive parsing, and that helps keep it very small. Naturally
there are recursive things in the language (nested if/then and loops
etc.) but these are implemented in Forth itself in a way which I won't
explain right now. It would be reduce the size of a Scheme considerably
if you didn't need a recursive reader.

I found out some other people have thought about it. There's
`Joy <http://www.latrobe.edu.au/philosophy/phimvt/joy.html>`__ and
`Factor <http://en.wikipedia.org/wiki/Factor_%28programming_language%29>`__
but they didn't go far enough, I think, and I wanted to explore really
deep functional ideas.

The part that is right, though, is to consider each "word" as a function
that takes a stack and returns a stack. All the interpreter does is
execute words in order, apply them to the stack. (See `Concatenative
programming
language <http://en.wikipedia.org/wiki/Concatenative_programming_language>`__).
However, you need some means of abstraction. In Forth you define a word
like this::

    : my-word ... ;

where ``:`` reads the next token and defines a new word in the dictionary,
then flips the interpreter into "compilation" mode, where instead of
executing words their addresses are pushed onto the end of the
dictionary. The ``;`` adds a ``return`` instruction to the dictionary and
flips the interpreter back into "immediate" mode where it runs words as
it reads them. It's extremely simple. Replace ``...`` with the words in
the body of the definition.

So what if it was an anonymous definition? Instead of defining a new
word in the dictionary the address where the words are compiled could
just be pushed onto the stack. I'll write the anonymous word definer as
``{`` and the end as ``}``. So instead of::

    : double 2 * ;
    5 double

which would print ``10``. You could write::

    5 { 2 * } execute

where ``execute`` calls the address at the top of the stack. Note the
syntax similarity to PostScript.

(Note: this immediately introduces problems of garbage collection, since
the compiled code is now inaccessible.)

I'm a fan of `Church
encoding <http://en.wikipedia.org/wiki/Church_encoding>`__ and the first
thing I think about in a language is how it might be achieved. I'm
particularly fond of Church encodings in `System
F <http://en.wikipedia.org/wiki/System_F>`__ but that's another story.

The Church booleans are

::

    true  ::= λxy.x
    false ::= λxy.y

So that

::

    true "yes" "no" --> "yes"
    false "yes" "no" --> "no"

In Fix, you could define these thus::

    true  ::= swap drop
    false ::= drop

(``swap`` is a Forth word which swaps the top two things on the stack,
``drop`` discards the top thing.)

So now

::

    "no" "yes" true --> "yes"
    "no" "yes" false --> "no"

Bear with me on the order reversal. It will make sense in a moment.
Consider the Church numbers, where the number N is something which
applies a function N times::

    0    ::= λfa.a
    1    ::= λfa.fa
    2    ::= λfa.f(fa)
    succ ::= λnfa.f(nfa)
    add  ::= λmn.m succ n   or λmnfa.mf(nfa)
    mul  ::= λmn.m (add n)  or λmnf.n(mf)
    exp  ::= λmn.nm

Well, in Fix, the number N can be encoded as something which executes
the top element of the stack N times, applying it to the rest of the
stack, without caring how many items it produces or consumes. So where
can we keep the thing being applied while the whole stack is fed to the
top thing? This problem occurs in Forth too, and there are two words
``>R`` and ``R>`` which transfer one thing from the operand stack to the
return stack, and vice versa. I hadn't realized it before, but thinking
back to the Forth I've written, these are exactly so you can do
higher-order stuff in Forth.

::

    0    ::= false          (See, I told you it would make sense.)
    1    ::= execute        (I'm going to start writing "1" for execute.)
    2    ::= dup >R 1 R> 1
    succ ::= {dup >R} swap cat {R> 1} cat

What?! OK, well it turns out that concatenating two sequences of words
is the same thing as composing two functions. So

::

    {a b c} 1 {d e f} 1

is the same as

::

    {a b c d e f} 1

So we introduce an operator ``cat`` which joins sequences:

::

    {a b c} {d e f} cat

(This wouldn't actually be implemented as list concatenation. It can
simply compile a two-word object that calls the first then second thing,
so it's a lot like a list cons.)

So let's see how ``succ`` works. Here's an execution trace. The stack is
on the left, the remaining program is on the right.

::

    0                       succ
    0                       {dup >R} swap cat {R> 1} cat
    0 {dup >R}              swap cat {R> 1} cat
    {dup >R} 0              cat {R> 1} cat
    {dup >R 0}              {R> 1} cat
    {dup >R 0} {R> 1}       cat
    {dup >R 0 R> 1}

It should be clear to see that ``dup >R 0 R>`` is a no-op, so this is the
same as ``1``. In general,

::

    n                       succ
    {dup >R}n{R> 1}

which is a function which executes the top thing on the stack one more
time than ``n``. So, now you can write ``{drop} 2`` and drop two things from
the stack! This is obviously a Good Thing.

::

    a b c                   {drop} 2
    a b c {drop}            2
    a b c {drop}            dup >R 1 R> 1
    a b c {drop} {drop}     >R 1 R> 1
    a b c {drop}            1 R> 1
    a b                     R> 1
    a b {drop}              1
    a

An aside about efficiency. WIth this definition, the number N uses O(N)
levels of the return stack, when there's clearly something better::

    3    ::= dup R> 1 R> dup R> 1 R> 1

On the other hand, there's no reason to just apply ``succ`` to numbers. I
haven't though of another use for it, but I bet there is one. Now::

    factorial ::=
        {1} {1} rot
        {over mul swap succ swap} swap 1
        swap drop

How does it work? Where's the recursion? Ha!

For my next trick, let's consider lists. There's something I like to
call "Church lists" by analogy with "Church numbers" even though I'm not
sure Church had anything to do with them. In Lambda calculus::

    nil     ::= λfa.a
    [x]     ::= λfa.fxa
    [x y]   ::= λfa.fy(fxa)
    [x y z] ::= λfa.fz(fy(fxa))
    cons    ::= λelfa.fe(lfa)

In other words, a list takes a function and an identity, and applies the
function to each element in turn. A list is represented by its own
``fold`` function. So::

    [1 2 3] + 0

would evaluate to 6, and

::

    [1 2 3] cons nil

evaluates to [3 2 1]. Let's do this in "Fix". First of all, I'm going to
define ``R@`` which copies the top element of the return stack to the
operand stack, and is equivalent to ``R> dup >R``.

::

    []      ::= 0           (Neato!)
    [x]     ::= >R x R@ 1 R> []
    [x y]   ::= >R x R@ 1 y R@ 1 R> []
    [x y z] ::= >R x R@ 1 y R@ 1 z R@ 1 R> []
    cons    ::= {>R} swap cat {R@ 1 R>} cat swap cat

Let's see ``cons`` in action::

    {[]} x                  cons
    {[]} x                  {>R} swap cat {R@ 1 R>} cat swap cat
    {[]} {>R}x{R@ 1 R>}     swap cat
    {>R}x{R@ 1 R> []}

In other words, it stashes a copy of the function, pushes x, appies the
function to it, and leaves another copy of the function for the rest of
the list. In this case the rest is [], which discards the function.
Let's try adding up the contents of a list::

    0 +                     [1 2 3]
    0 +                     >R {1} R@ 1 R> [2 3]
    0                       {1} R@ 1 R> [2 3]
    0 1                     R@ 1 R> [2 3]
    0 1 +                   1 R> [2 3]
    1                       R> [2 3]
    1 +                     [2 3]
    1 +                     >R {2} R@ 1 R> [3]
    1 2 +                   1 R> [3]
    3 +                     [3]
    3 +                     >R {3} R@ 1 R> []
    3 3 +                   1 R> []
    6 +                     []
    6

I'll leave executing ``[] cons [1 2 3]`` as an exercise.

One of the consequences of making numbers, booleans, etc. functions is
that you have to defer execution of them if you don't want them to do
anything. So to get a literal number 5 on the stack you have to say
``{5}`` in your code. Otherwise 5 will execute and call the top thing on
the stack five times.

So what are these braces? Well, the open brace pushes the compile
pointer onto the stack and flips the interpreter into "compile" mode, to
start compiling subsequent words. When the close brace is reached it
appends a "return" opcode and flips back to execute mode. But what about
nesting? It's clear that we want programs like::

    {0} < {{"non-negative"}} {{"negative"}} rot 1 print

It's time to talk about how Forth does ``IF``. Remember that Forth's
syntax is a bit weird::

    0 < IF ." negative" ELSE ." non-negative" ENDIF

When a Forth word is defined it can be declared as "immediate", which
means that it gets run straight away even when the interpreter is
compiling. The word can therefore mess with the compiler state or do
some compiling itself. ``IF`` is immediate, and typically does something
like this:

#. Push the current compilation pointer (what will be the PC).
#. Compile a conditional branch but leave the destination address empty.
   (In Forth this means compiling a call to a word which implements the
   run-time semantics of ``IF`` by messing with its return address, since
   all instructions are CALLs.)

What ``ENDIF`` does it to fill in the branch at the address on the stack
to point to the current compilation pointer. So it's back-patching the
IF branch. ELSE does this:

#. Push the compilation pointer.
#. Compile an unconditional branch with no destination.
#. swap
#. Back-patch the IF branch at the top of stack.

So what about when you're compiling and you meet a ``{``? Well, it turns
out to be very simple. You just push the CP and compile a dummy CALL.
When you reach a ``}`` you compile a return, then back-patch the CALL to
come to the current CP, then compile a ``R>``. At run-time, this will copy
the address of the instruction after the CALL to the stack, which is the
entry point of the code block.

It nests.

Consider::

    dup {0} > {drop {{"negative"}} {{0} = {{"zero"}} {{"positive"}} rot 1} rot 1 print

(Don't worry about the double braces around the strings for the moment.)
I'm going to hand-compile this into a sort of psuedo-assembler.
Fortunately this is trivial.

::

        CALL dup
        CALL l0
        CALL 0
        RET
    l0: CALL R>
        CALL >
        CALL l1
        CALL drop
        PUSH "negative"
        RET
    l1: CALL R>
        CALL l2
        CALL l3
        CALL 0
        RET
    l3: CALL R>
        CALL =
        CALL l4
        PUSH "zero"
        RET
    l4: CALL R>
        CALL l5
        PUSH "positive"
        RET
    l5: CALL R>
        CALL ROT
        CALL 1
        RET
    l2: CALL R>
        CALL ROT
        CALL 1
        CALL print

(Please don't worry about how ``>`` and ``=`` work for the moment, or the
fact that ``{w}`` can be optimised, and especially ``{0}``.)

So the only other things that ``{`` and ``}`` need to do is keep track of a
nesting level and switch back to immediate execution mode. This only
complicates things slightly. ``{`` needs to push two things instead of one
-- the CP and the mode -- and ``}`` needs to restore the mode.

If I'm right, nothing else is needed for flow control. (By the way, this
is not how PostScript does it.)

More about quoting. In Lisp, some things need quoting and some don't.
Numbers, for example, don't need to be quoted, because their result is
themselves. Forth is similar: "executing" a number pushes it on to the
stack. In my proposal this is not the case: numbers, booleans, and lists
are functions. Strings ought to be too. So what is the representation of
one of these things? It has a lot to do with boxing.

Mostly, we accept the idea that we represent functions by points to
something. It's the same here. ``2`` could be represented by a pointer to
something which runs the top thing on the stack twice. (Forget about
optimising this for a moment.) But if you just say ``2`` then it runs! If
you say ``{2}`` then you get a pointer to something which runs the top
thing on the stack twice, in other words, 2. There's something strange
going on here: it's like function abstraction and quoting have become
the same thing.

In theory, all the numbers appear in the dictionary of definitions where
we find things like ``drop`` and ``dup``, and which we extend when we define
new words. So in theory there's a word ``2`` which we can look up to get
its entry point. But if we use tagging, then we can just use a binary
representation of 2 as the representation of the 2 function.

Furthermore, a real implementation can easily spot that for any word,
``{word}`` is equivalent to the entry point of the word, and can push that
instead. It's only when there's a sequence of words in brackets that we
need to build new code to compose the operations inside.

A note on strings. If strings are lists of characters then we expect
them to be self-folders, so if ``emit`` sends one character to the screen,
this works::

    {emit} "Hello, world!"

because it's like::

    {emit} ['H' 'e' 'l' 'l' 'o' ',' ' ' 'w' 'o' 'r' 'l' 'd' '!']

The string is a function which applies the top thing on the stack to
each of its characters in turn. To stop the string running we have to
quote it.

Now, cunningly, my earlier program

::

    dup {0} > {drop {{"negative"}} {{0} = {{"zero"}} {{"positive"}} rot 1} rot 1 print

could be written

::

    {emit} dup {0} > {drop "negative"} {{0} = {"zero"} {"positive"} rot 1} rot 1

Anyway, about loops and recursion. "Who needs 'em?" is what I say. Every
piece of data is a loop over itself. What else are you going to do? My
factorial says::

    {1} {1} rot {over mul swap succ swap} swap 1 swap drop

The two 1s are the counter and the accumulated total so far, then it
simply repeats the ``over mul swap succ swap`` N times.

But what about recursion? Well, there are fixed point combinators.
Curry's Y is

::

    Y = λf.(λx.f(xx))(λx.f(xx))

So that's

::

    {dup 1} swap cat dup 1

Let's try it.

::

    f           {dup 1} swap cat dup 1
    {dup 1 f}       dup 1
    {dup 1 f} {dup 1 f} 1
    {dup 1 f}       dup 1 f
    {dup 1 f}　{dup 1 f} 1 f
    {dup 1 f}　      dup 1 f f
    {dup 1 f} {dup 1 f} 1 f f
    {dup 1 f}       dup 1 f f f
    {dup 1 f} {dup 1 f} 1 f f f
        etc.

So it's non-terminating but is definitely producing a recursion of the
function in some sense. Perhaps what we need is the applicative-order
fixed point combinator

::

    Y = λf.(λx.f(λy.xxy))(λx.f(λy.xxy))

So we just need Y to feed the function to itself and the stack when it's
applied. To do this we need an operator ``defer`` which turns the top
thing on the stack into an operator which pushes that thing back on the
stack when run, so that ``defer 1`` is a no-op. You can think of this as
adding a layer of braces. (Or, you can notice that it is
eta-abstraction.) Then::

    Y ::= {defer {dup 1} cat} swap cat dup 1

Here's a recursive factorial written with the Y combinator.

::

    {swap dup {0} = {dup pred rot 1 mul} {{drop} 2 {1}} rot 1} Y

Let's try it. I'm writing ``F`` for the recursive part of factorial.

::

    2 F                                   {defer {dup 1} cat} swap cat dup 1
    2 {defer {dup 1} cat}F                dup 1
    2 {defer {dup 1} cat}F                defer {dup 1} cat F
    2 {{defer {dup 1} cat}F dup 1}        F
    {{defer {dup 1} cat}F dup 1} 2        dup pred rot 1 mul
    {{defer {dup 1} cat}F dup 1} 2 1      rot 1 mul
    2 1 {{defer {dup 1} cat}F dup 1}      1 mul
    2 1                                   {defer {dup 1} cat}F dup 1 mul
    2 1 {defer {dup 1} cat}F              dup 1 mul
    2 1 {defer {dup 1} cat}F              defer {dup 1} cat F mul
    2 1 {{defer {dup 1} cat}F dup 1}      F mul
    2 1 0                                 {defer {dup 1} cat}F dup 1 mul mul
    2 1 0 {defer {dup 1} cat}F            dup 1 mul mul
    2 1 0 {defer {dup 1} cat}F dup 1}     F mul mul
    2 1 0 {defer {dup 1} cat}F dup 1}     {drop} 2 {1} mul mul
    2 1 1                                 mul mul
    2

I think it's time I implemented the interpreter and compiler to find out
what they look like.
