# NPython

[![CI (C/JS Test)](https://github.com/nimpylib/npython/actions/workflows/ci.yml/badge.svg)](https://github.com/nimpylib/NPython/actions/workflows/ci.yml)
[![CD (play build)][play-badge]](https://github.com/nimpylib/npython/actions/workflows/playground.yml)
[![docs](https://github.com/nimpylib/npython/actions/workflows/docs.yml/badge.svg)][docs]

[docs]: https://npython.nimpylib.org
[play-badge]: https://github.com/nimpylib/npython/actions/workflows/playground.yml/badge.svg

Python programming VM implemented in Nim.

<!--a tick to minic tow columns-->

|||
|-|-|
|[Online `playground` demo][play-npython] ↓ | [Read API Docs][docs]|
|(by compiling Nim to Javascript) | [Wiki about History](https://github.com/nimpylib/npython/wiki/History)|


[play-npython]: https://play.nimpylib.org/

### Purpose
- Fun and practice. Learn both Python and Nim.
- Serve as a altertive small version of CPython
  (as of 0.1.1, less than 2MB on release build mode)


### How to use

#### Easiest installation

```shell
nimble install npython
```

Then you can use as if using `python`, e.g.

```shell
npython --version
npython -c "print('hello, NPython')"
```

#### Manually Install (e.g. JS backend)
Or you may wanna build for js backend or something else:

##### prepare

```
git clone https://github.com/nimpylib/npython.git
cd npython
```

NPython support C backend and multiply JS backends:

> after build passing `-h` flag to npython and you will
see help message

##### For a binary executable (C backend)

```
nimble build
bin/npython
```

##### For JS backend

- NodeJS: `nimble buildJs -d:nodejs`
- Deno: `nimble buildJs -d:deno`
- Browser, prompt&alert-based repl: `nimble buildJs -d:jsAlert`
- single page website: `nimble buildKarax` (requires `nimble install karax`). This is how [online playground][play-npython] runs


### Status
Capable of:
* flow control with `if else`, `while`, `for`, ...
* function (closure) defination and call. Decorators.
* builtin print, dir, len, range, tuple, list, dict, exceptions, etc.
* import such as `import foo`.
* raise exceptions, basic `try ... except XXXError ... `, with detailed traceback message. Assert statement.
* interactive mode and file mode
* ...

Check out [`./tests`](./tests/) to see more examples.

### Todo
* integrate with [nimpylib](https://github.com/nimpylib/nimpylib)
* builtin compat dict
* better bigint lib
* ... ref [Todo on Wiki](https://github.com/nimpylib/npython/wiki)

