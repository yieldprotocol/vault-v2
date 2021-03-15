## Naming
When a concept or process has been defined by MakerDAO, their terminology will be reused.
When a concept or process is yet to be defined, up to 8 letter words will be found, using a leifmotif to correlate them.

## Access Control
Functions preceded by two underscores `_pour` are internal to the contract. Only the same contract can call them.
Functions preceded by one underscore `pour` are internal to the system. Only contracts with `auth` for that function can call them.
Functions not preceded by underscores `pour` are public, and end users can call them.
Variables or argumens that are internal to a function will be followed by an underscore `series_` when necessary for them not to clash with a state variable or function.