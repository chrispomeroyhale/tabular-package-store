# TabularPackageStore (`tabular-package-store`)
This is a Swift implementation of a CoreData NSAtomicStore for loading a Tabular Data Package into a CoreData object graph.

In practice this is useful for importing or exporting between a CoreData object graph and a Tabular Data Package.

CoreData's NSAtomicStore is not efficient and as such this is not intended as a main backing store. Doing so would result in each save requiring re-exporting.

There's not much information about how to set up NSAtomicStores and this code has been working in production. This is tailor made for one specific app and is not really intended for broad use, and it's not up to date on modern Swift conventions and expectations, but it could be forked to suit another project's needs. It is not quite up to the standards I would have liked.

There's also no migration support. Or maybe it does for some simple cases. It's provided as-is.

## Dependencies
The Swift implementations of DataPackage and TableSchema were originally derived from this. They were split and open sourced long ago as part of a Frictionless Data initiative.

The DialectalCSV was also purpose built initially for use in conjunction with this and TableSchema to be able to support the different "flavors" of CSV.
