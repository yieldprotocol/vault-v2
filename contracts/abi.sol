contract Join {
    function join(address usr, uint wad)
    function exit(address usr, uint wad)

}

contract fyTokenJoin {
    function join(address usr, uint wad)
    function exit(address usr, uint wad)

}


contract YieldVat {


    // collateral from/to Gem
    function slip(bytes32 collateral, address usr, int256 wad)

    // from gem to Vault
    function post(bytes32 collateral, bytes32 series, address from, address vault, uint256 amount)

    // from Vault to Gem
    function withdraw(IERC20 collateral, address from, address to, Vault vault, uint256 amount)
    


    // move collateral from one vault to another (like when rolling a series)
    function move(bytes32 collateral, bytes32 fromSeries, address from, bytes32 toSeries, address to, uint256 amount)

    // fork vaults of the same series 
    function fork(bytes32 collateral, bytes32 fromSeries, address from, address to, int256 collateral, int256 amount)


    //borrowing operations 

    // borrow from vault, send borrowed asset to gem account 
    function borrow(bytes32 collateral, bytes32 series, address vault, address to, uint256 amount)
    
    // repay vault debt from gem account using fyTokens
    function repay(bytes32 collateral, bytes32 series, address vault, address from, uint256 amount)
    
    //repay vault debt from gem account using underlying token 
    function repayWithUnderlying(bytes32 collateral, bytes32 series, address vault, address from, uint256 amount)





    // Possible optimizations by bypassing Gem

    /// bypass gem place directly in vault
    function postDirect(bytes32 collateral, bytes32 series, address vault, int256 amount)

}