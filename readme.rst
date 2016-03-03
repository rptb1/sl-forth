=================
Second Life Forth
=================

:Author: Richard Brooksby
:Date: 2016-03-03

This is an implementation of a tiny Forth-like language implemented in
Linden Scripting Language.  It runs as a collection of script tasks
inside Second Life objects.

I wrote it because in LSL you can't write simple things like:

  x = rez("box");
  give(x, "thing");
  give(x, "another thing");

(For further details, see section "The Problem" of `the manual`_.)

.. _`the manual`: Manual.rst

This interpreter was genuinely useful and made me real money!  It made
it possible for me to re-pack all the virtual goods in my virtual shop
in minutes, rather than it taking me hours by hand.  Without this, I
simply would not have made a profit when I modified my goods.  Shop
automation was the key to making a profit in Second Life, and I funded
several trips to the Game Development Conference in San Francisco from
my Second Life earnings.

I wrote `this article`_ about a theoretical language called "Fix" based on my
experience making this [RB-2008-01-20]_.

.. _`this article`: fix.rst

References
----------

.. [RB-2008-01-20] "Fix"; Richard Brooksby; 2008-01-20;
   <http://chard.livejournal.com/56744.html>.
