contract Join {
    // --- Auth ---
    mapping (address => uint) public wards;
    function rely(address usr) external auth { wards[usr] = 1; }
    function deny(address usr) external auth { wards[usr] = 0; }
    modifier auth {
        require(wards[msg.sender] == 1, "GemJoin/not-authorized");
        _;
    }

    IERC20  public token;
    bytes6  public ilk;   // Collateral Type
    uint    public dec;
    uint    public live;  // Active Flag

    constructor(address vat_, bytes6 ilk_, address token_) public {
        wards[msg.sender] = 1;
        wards[vat_] = 1;
        token = IERC20(token_);
        ilk = ilk_;
        dec = token.decimals();
        live = 1;
    }

    function cage() external auth {
        live = 0;
    }

    function join(address usr, int wad) external auth returns (int128) {
        if (wad > 0) {
            require(live == 1, "GemJoin/not-live");
            require(token.transferFrom(usr, address(this), wad), "GemJoin/failed-transfer");
        } else {
            require(token.transfer(usr, wad), "GemJoin/failed-transfer");
        }
        return wad;                    // Use this to record in vat a balance different from the amount joined
    }
}