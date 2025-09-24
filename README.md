# NPython

(Subset of) Python programming language implemented in Nim, from the compiler to the VM.

[Online interactive demo by compiling Nim to Javascript][play-npython].

[play-npython]: https://play.nimpylib.org/

### Purpose
- Fun and practice. Learn both Python and Nim.
- Serve as a altertive small version of CPython
  (as of 0.1.1, less than 2MB on release build mode)


### Status
Capable of:
* flow control with `if else`, `while` and `for`
* basic function (closure) defination and call. Decorators.
* builtin print, dir, len, range, tuple, list, dict, exceptions and bunch of other simple helper functions
* list comprehension (no set or dict yet).
* basic import such as `import foo`. No alias, no `from`, etc
* raise exceptions, basic `try ... except XXXError ... `, with detailed traceback message. Assert statement.
* primitive `class` defination. No inheritance, no metatype, etc
* interactive mode and file mode

Check out `./tests` to see more examples.


### How to use

#### prepare

```
git clone https://github.com/nimpylib/npython.git
cd npython
```

NPython support C backend and multiply JS backends:

> after build passing `-h` flag to npython and you will
see help message

#### For a binary executable (C backend)

```
nimble build
bin/npython
```

#### For JS backend

- NodeJS: `nimble buildJs -d:nodejs`
- Deno: `nimble buildJs -d:deno`
- Browser, prompt&alert-based repl: `nimble buildJs -d:jsAlert`
- single page website: `nimble buildKarax` (requires `nimble install karax`). This is how [online playground][play-npython] runs


### Todo
* more features on user defined class
* builtin compat dict
* yield stmt
* better bigint lib

### Performance
Nim is claimed to be as fast as C, and indeed it is. According to some primitive micro benchmarks (`spin.py` and `f_spin.py` in `tests/benchmark/`), although NPython is currently 5x-10x slower than CPython 3.7, it is at least in some cases faster than CPython < 2.4. This is already a huge achievement considering the numerous optimizations out there in the CPython codebase and NPython is focused on quick prototyping and lefts many rooms for optimization. For comparison, [RustPython0.0.1](https://github.com/RustPython/RustPython) is 100x slower than CPython3.7 and uses 10x more memory.

Currently, the performance bottlenecks are object allocation, seq accessing (compared with CPython direct memory accessing). The object allocation and seq accessing issue are basically impossible to solve unless we do GC on our own just like CPython. 


### Drawbacks
NPython aims for both C and JavaScript targets, so it's hard (if not impossible) to perform low-level address based optimization.

#### Nim 0.x GC
NPython relies on Nim GC. Frankly speaking, in the past, it was not satisfactory. 
* The GC used thread-local heap, which once made threading once nearly impossible (for Python), though not so for Nimv1 and Nimv2.
* The GC could hardly be shared between different dynamic libs, which meant NPython can not import extensions written in Nim.

If memory was managed manually, these drawbacks could be overcomed early.

#### Nim v1 and v2 MM
However, in current years, Nim, specially v2, has improved a lot on GC,
which's now called MM(Memory Management).

And Nimv2 uses ORC by default, which offers deterministic performance and uses a shared heap.

Not only has threading programming been enhanced and become easy to write,
but also `setupForeignThreadGc()` and `tearDownForeignThreadGc()` come out here
for foreignal call to control Nim's MM.

In short those difficulties that once held us back have disappeared.



