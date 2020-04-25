pragma solidity ^0.5.2;


/// @dev Interface to interact with the `Join.sol` contract from MakerDAO
interface IDaiJoin {
    function rely(address usr) external;
    function deny(address usr) external;
    function cage() external;
    function join(address usr) external;
    function exit(address usr, uint wad) external;
}