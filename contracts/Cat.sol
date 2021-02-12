// Token balances will be kept in the join, for flexibility in their management
contract TokenJoin {
    function join(address usr, uint wad)
    function exit(address usr, uint wad)

}

contract FYTokenJoin {
    function join(address usr, uint wad)
    function exit(address usr, uint wad)

}


contract Cat {
  
    // Put an undercollateralized vault up for liquidation.
    function grab(bytes12 vault)
        public
    {
        vat._grab(vault);
    }

    // Release a vault. It doesn't need to be collateralized, and it doesn't need to go back to its previous owner (can be sold).
    function free(bytes12 vault)
        public
    {
        vat._free(vault);
    }

    // Buy an amount of collateral off a vault in liquidation, paying at most `max` underlying.
    function buy(bytes12 vault, address ilk, uint128 ink, uint128 max)
        public
    {
        // _frob already checks that the vault is valid.
        int128 art = price(vault, ilk, ink);                              // Cost of `price`
        require (art <= max, "Too expensive to buy");
        // TODO: Tweak `_frob` so that it takes the `art` from `msg.sender`, and sends the `ink` to him as well.
        vat._frob(vault, ilk.toBytes1(), ink.toArray(), art);             // Cost of `vat._frob`
    }

    function price(bytes12 vault, address ilk, uint128 ink)
        public
        view
        returns (int128)
    {
        // Let fail if the vault doesn't exist?
        // Let fail if the vault doesn't have the right ilk?
        // Let fail if the vault doesn't have enough ink?
        uint32 timestamp = vat.timestamp(vault);                          // 1 SLOAD + 700 + 12*16
        require (timestamp > 0, "Not for sale");
        Ilks memory ilks = vat.vaultIlks(vault);                          // 1 SLOAD + 700 + 12*16. Maybe not needed.
        Balances memory balances = vat.vaultBalances(vault);              // 2 SLOAD + 700 + 12*16. Maybe only 1 SLOAD needed.
        // Math here
        return _price
    }   
    }
}