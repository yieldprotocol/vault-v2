This directory contains contracts to use Ether as a borrowable asset.

The original Ladle implementation includes functions to wrap and unwrap Ether, but unfortunately it assumes that the only possible destination is the Join for Wrapped Ether. When adding Ether as a borrowable asset the Pools also become a valid destination for Wrapped Ether.

The simplest solution is to implement a module to wrap ether received by the Ladle and push it to any destination.

ladle.moduleCall{ value: etherToWrap }(
    WrapEtherModule,
    wrap(receiver, etherToWrap)
)