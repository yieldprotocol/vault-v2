pragma solidity ^0.5.2;
pragma experimental ABIEncoderV2;

import './Oracle.sol';
import "@nomiclabs/buidler/console.sol";
import '@openzeppelin/contracts/token/ERC20/ERC20Mintable.sol';
import '@openzeppelin/contracts/token/ERC20/ERC20Burnable.sol';

contract yTokenOld is ERC20Burnable, ERC20Mintable {
  uint256 public when;

  constructor(uint256 when_) public {
      when = when_;
  }

  function burnByOwner(address account, uint256 amount) external onlyMinter {
    _burn(account, amount);
  }

}


contract Treasurer {
  struct Repo {
      uint256 locked;   // Locked Collateral
      uint256 unminted;   // unminted
      uint256 debt;     // Debt
  }

  struct yieldT {
      address where;  // contract address of yTokenOld
      uint256 when;   // maturity time of yTokenOld
  }

  mapping (uint    => yieldT) public yTokens;
  mapping (uint    => mapping (address => Repo)) public repos; // locked ETH and debt
  mapping (address => uint) public unlocked;  // unlocked ETH
  mapping (uint    => uint) public settled; // settlement price of collateral
  uint[] public issuedSeries;
  address public owner;
  address public oracle;
  uint public collateralRatio;                        // collateralization ratio
  uint public minCollateralRatio;                     // minimum collateralization ratio
  uint public totalSeries = 0;

  constructor(address owner_, uint collateralRatio_, uint minCollateralRatio_) public {
    owner = owner_;
    collateralRatio = collateralRatio_;
    minCollateralRatio = minCollateralRatio_;
  }

  // --- Math ---
  uint constant WAD = 10 ** 18;
  uint constant RAY = 10 ** 27;
  function add(uint x, uint y) internal pure returns (uint z) {
    z = x + y;
    require(z >= x, "treasurer-add-z-not-greater-eq-x");
  }

  function sub(uint x, uint y) internal pure returns (uint z) {
    require((z = x - y) <= x, "treasurer-sub-failed");
  }

  function mul(uint x, uint y) internal pure returns (uint z) {
    require(y == 0 || (z = x * y) / y == x,  "treasurer-mul-failed");
  }

  function wmul(uint x, uint y) internal pure returns (uint z) {
    z = add(mul(x, y), WAD / 2) / WAD;
  }

  function wdiv(uint x, uint y) internal pure returns (uint z) {
    z = add(mul(x, WAD), y / 2) / y;
  }

  // --- Views ---

  // return unlocked collateral balance
  function balance(address usr) public view returns (uint){
    return unlocked[usr];
  }

  // --- Actions ---

  // provide address to oracle
  // oracle_ - address of the oracle contract
  function setOracle(address oracle_) external {
    require(msg.sender == owner);
    oracle = oracle_;
  }

  // get oracle value
  function peek() public view returns (uint r){
    Oracle _oracle = Oracle(oracle);
    r = _oracle.read();
  }

  // issue new yToken
  function issue(uint256 when) external returns (uint series) {
    require(msg.sender == owner, "treasurer-issue-only-owner-may-issue");
    require(when > now, "treasurer-issue-maturity-is-in-past");
    series = totalSeries;
    require(yTokens[series].when == 0, "treasurer-issue-may-not-reissue-series");
    yTokenOld _token = new yTokenOld(when);
    address _a = address(_token);
    yieldT memory yT = yieldT(_a, when);
    yTokens[series] = yT;
    issuedSeries.push(series);
    totalSeries = totalSeries + 1;
  }

  // add collateral to repo
  function join() external payable {
    require(msg.value >= 0, "treasurer-join-collateralRatio-include-deposit");
    unlocked[msg.sender] = add(unlocked[msg.sender], msg.value);
  }

  // remove collateral from repo
  // amount - amount of ETH to remove from unlocked account
  // TO-DO: Update as described in https://diligence.consensys.net/posts/2019/09/stop-using-soliditys-transfer-now/
  function exit(uint amount) external {
    require(amount >= 0, "treasurer-exit-insufficient-balance");
    unlocked[msg.sender] = sub(unlocked[msg.sender], amount);
    msg.sender.transfer(amount);
  }

  // make a new yToken
  // series - yToken to mint
  // made   - amount of yToken to mint
  // paid   - amount of collateral to lock up
  function make(uint series, uint made, uint paid) external {
    require(series < totalSeries, "treasurer-make-unissued-series");
    // first check if sufficient capital to lock up
    require(unlocked[msg.sender] >= paid, "treasurer-make-insufficient-unlocked-to-lock");

    Repo memory repo = repos[series][msg.sender];
    uint rate        = peek(); // to add rate getter!!!
    uint256 min      = wmul(wmul(made, collateralRatio), rate);
    require (paid >= min, "treasurer-make-insufficient-collateral-for-those-tokens");

    // lock msg.sender Collateral, add debt
    unlocked[msg.sender]      = sub(unlocked[msg.sender], paid);
    repo.locked               = add(repo.locked, paid);
    repo.debt                 = add(repo.debt, made);
    repos[series][msg.sender] = repo;

    // mint new yTokens
    // first, ensure yToken is initialized and matures in the future
    require(yTokens[series].when > now, "treasurer-make-invalid-or-matured-ytoken");
    yTokenOld yT  = yTokenOld(yTokens[series].where);
    address sender = msg.sender;
    yT.mint(sender, made);
  }

  // check that wipe leaves sufficient collateral
  // series - yToken to mint
  // credit   - amount of yToken to wipe
  // released  - amount of collateral to free
  // returns (true, 0) if sufficient collateral would remain
  // returns (false, deficiency) if sufficient collateral would not remain
  function wipeCheck(uint series, uint credit, uint released) public view returns (bool, uint) {
    require(series < totalSeries, "treasurer-wipeCheck-unissued-series");
    Repo memory repo        = repos[series][msg.sender];
    require(repo.locked >= released, "treasurer-wipe-release-more-than-locked");
    require(repo.debt >= credit,     "treasurer-wipe-wipe-more-debt-than-present");
    // if would be undercollateralized after freeing clean, fail
    uint rlocked  = sub(repo.locked, released);
    uint rdebt    = sub(repo.debt, credit);
    uint rate     = peek(); // to add rate getter!!!
    uint256 min   = wmul(wmul(rdebt, collateralRatio), rate);
    uint deficiency = 0;
    if (min >= rlocked){
      deficiency = sub(min, rlocked);
    }
    return (rlocked >= min, deficiency);
  }

  // wipe repo debt with yToken
  // series - yToken to mint
  // credit   - amount of yToken to wipe
  // released  - amount of collateral to free
  function wipe(uint series, uint credit, uint released) external {
    require(series < totalSeries, "treasurer-wipe-unissued-series");
    // if yToken has matured, should call resolve
    require(now < yTokens[series].when, "treasurer-wipe-yToken-has-matured");

    Repo memory repo        = repos[series][msg.sender];
    require(repo.locked >= released, "treasurer-wipe-release-more-than-locked");
    require(repo.debt >= credit,     "treasurer-wipe-wipe-more-debt-than-present");
    // if would be undercollateralized after freeing clean, fail
    uint rlocked  = sub(repo.locked, released);
    uint rdebt    = sub(repo.debt, credit);
    uint rate     = peek(); // to add rate getter!!!
    uint256 min   = wmul(wmul(rdebt, collateralRatio), rate);
    require(rlocked >= min, "treasurer-wipe-insufficient-remaining-collateral");

    //burn tokens
    yTokenOld yT  = yTokenOld(yTokens[series].where);
    require(yT.balanceOf(msg.sender) > credit, "treasurer-wipe-insufficient-token-balance");
    yT.burnFrom(msg.sender, credit);

    // reduce the collateral and the debt
    repo.locked               = sub(repo.locked, released);
    repo.debt                 = sub(repo.debt, credit);
    repos[series][msg.sender] = repo;

    // add collateral back to the unlocked
    unlocked[msg.sender] = add(unlocked[msg.sender], released);
  }

  // liquidate a repo
  // series - yToken of debt to buy
  // bum    - owner of the undercollateralized repo
  // amount - amount of yToken debt to buy
  function liquidate(uint series, address bum, uint256 amount) external {
    require(series < totalSeries, "treasurer-liquidate-unissued-series");
    //check that repo is in danger zone
    Repo memory repo  = repos[series][bum];
    uint rate         = peek(); // to add rate getter!!!
    uint256 min       = wmul(wmul(repo.debt, minCollateralRatio), rate);
    require(repo.locked < min, "treasurer-bite-still-safe");

    //burn tokens
    yTokenOld yT  = yTokenOld(yTokens[series].where);
    yT.burnByOwner(msg.sender, amount);

    //update repo
    uint256 bitten     = wmul(wmul(amount, minCollateralRatio), rate);
    repo.locked        = sub(repo.locked, bitten);
    repo.debt          = sub(repo.debt, amount);
    repos[series][bum] = repo;

    // send bitten funds
    msg.sender.transfer(bitten);
  }

  // trigger settlement
  // series - yToken of debt to settle
  function settlement(uint series) external {
    require(series < totalSeries, "treasurer-settlement-unissued-series");
    require(now > yTokens[series].when, "treasurer-settlement-yToken-hasnt-matured");
    require(settled[series] == 0, "treasurer-settlement-settlement-already-called");
    settled[series] = peek();
  }


  // redeem tokens for underlying Ether
  // series - matured yToken
  // amount    - amount of yToken to close
  function withdraw(uint series, uint256 amount) external {
    require(series < totalSeries, "treasurer-withdraw-unissued-series");
    require(now > yTokens[series].when, "treasurer-withdraw-yToken-hasnt-matured");
    require(settled[series] != 0, "treasurer-settlement-settlement-not-yet-called");

    yTokenOld yT  = yTokenOld(yTokens[series].where);
    yT.burnByOwner(msg.sender, amount);

    uint rate     = settled[series];
    uint256 goods = wmul(amount, rate);
    msg.sender.transfer(goods);
  }

  // close repo and retrieve remaining Ether
  // series - matured yToken
  function close(uint series) external {
    require(series < totalSeries, "treasurer-close-unissued-series");
    require(now > yTokens[series].when, "treasurer-withdraw-yToken-hasnt-matured");
    require(settled[series] != 0, "treasurer-settlement-settlement-not-yet-called");

    Repo memory repo = repos[series][msg.sender];
    uint rate        = settled[series]; // to add rate getter!!!
    uint remainder   = wmul(repo.debt, rate);

    require(repo.locked > remainder, "treasurer-settlement-repo-underfunded-at-settlement" );
    uint256 goods  = sub(repo.locked, wmul(repo.debt, rate));
    repo.locked    = 0;
    repo.debt      = 0;
    repos[series][msg.sender] = repo;

    msg.sender.transfer(goods);
  }
}
