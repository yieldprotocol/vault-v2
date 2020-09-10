// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.5.0 || ^0.6.0;

import "../pool/YieldMath.sol";

/**
 * Wrapper for Yield Math Smart Contract Library, with return values for reverts.
 */
contract YieldMathWrapper {
  /**
   * Calculate the amount of eDai a user would get for given amount of DAI.
   *
   * @param daiReserves DAI reserves amount
   * @param eDaiReserves eDai reserves amount
   * @param daiAmount DAI amount to be traded
   * @param timeTillMaturity time till maturity in seconds
   * @param k time till maturity coefficient, multiplied by 2^64
   * @param g fee coefficient, multiplied by 2^64
   * @return the amount of eDai a user would get for given amount of DAI
   */
  function eDaiOutForDaiIn (
    uint128 daiReserves, uint128 eDaiReserves, uint128 daiAmount,
    uint128 timeTillMaturity, int128 k, int128 g)
  public pure returns (bool, uint128) {
    return (
      true,
      YieldMath.eDaiOutForDaiIn (
        daiReserves, eDaiReserves, daiAmount, timeTillMaturity, k, g));
  }

  /**
   * Calculate the amount of DAI a user would get for certain amount of eDai.
   *
   * @param daiReserves DAI reserves amount
   * @param eDaiReserves eDai reserves amount
   * @param eDaiAmount eDai amount to be traded
   * @param timeTillMaturity time till maturity in seconds
   * @param k time till maturity coefficient, multiplied by 2^64
   * @param g fee coefficient, multiplied by 2^64
   * @return the amount of DAI a user would get for given amount of eDai
   */
  function daiOutForEDaiIn (
    uint128 daiReserves, uint128 eDaiReserves, uint128 eDaiAmount,
    uint128 timeTillMaturity, int128 k, int128 g)
  public pure returns (bool, uint128) {
    return (
      true,
      YieldMath.daiOutForEDaiIn (
        daiReserves, eDaiReserves, eDaiAmount, timeTillMaturity, k, g));
  }

  /**
   * Calculate the amount of eDai a user could sell for given amount of DAI.
   *
   * @param daiReserves DAI reserves amount
   * @param eDaiReserves eDai reserves amount
   * @param daiAmount DAI amount to be traded
   * @param timeTillMaturity time till maturity in seconds
   * @param k time till maturity coefficient, multiplied by 2^64
   * @param g fee coefficient, multiplied by 2^64
   * @return the amount of eDai a user could sell for given amount of DAI
   */
  function eDaiInForDaiOut (
    uint128 daiReserves, uint128 eDaiReserves, uint128 daiAmount,
    uint128 timeTillMaturity, int128 k, int128 g)
  public pure returns (bool, uint128) {
    return (
      true,
      YieldMath.eDaiInForDaiOut (
        daiReserves, eDaiReserves, daiAmount, timeTillMaturity, k, g));
  }

  /**
   * Calculate the amount of DAI a user would have to pay for certain amount of
   * eDai.
   *
   * @param daiReserves DAI reserves amount
   * @param eDaiReserves eDai reserves amount
   * @param eDaiAmount eDai amount to be traded
   * @param timeTillMaturity time till maturity in seconds
   * @param k time till maturity coefficient, multiplied by 2^64
   * @param g fee coefficient, multiplied by 2^64
   * @return the amount of DAI a user would have to pay for given amount of
   *         eDai
   */
  function daiInForEDaiOut (
    uint128 daiReserves, uint128 eDaiReserves, uint128 eDaiAmount,
    uint128 timeTillMaturity, int128 k, int128 g)
  public pure returns (bool, uint128) {
    return (
      true,
      YieldMath.daiInForEDaiOut (
        daiReserves, eDaiReserves, eDaiAmount, timeTillMaturity, k, g));
  }

  /**
   * Raise given number x into power specified as a simple fraction y/z and then
   * multiply the result by the normalization factor 2^(128 * (1 - y/z)).
   * Revert if z is zero, or if both x and y are zeros.
   *
   * @param x number to raise into given power y/z
   * @param y numerator of the power to raise x into
   * @param z denominator of the power to raise x into
   * @return x raised into power y/z and then multiplied by 2^(128 * (1 - y/z))
   */
  function pow (uint128 x, uint128 y, uint128 z)
  public pure returns (bool, uint128) {
    return (
      true,
      YieldMath.pow (x, y, z));
  }

  /**
   * Calculate base 2 logarithm of an unsigned 128-bit integer number.  Revert
   * in case x is zero.
   *
   * @param x number to calculate 2-base logarithm of
   * @return 2-base logarithm of x, multiplied by 2^121
   */
  function log_2 (uint128 x)
  public pure returns (bool, uint128) {
    return (
      true,
      YieldMath.log_2 (x));
  }

  /**
   * Calculate 2 raised into given power.
   *
   * @param x power to raise 2 into, multiplied by 2^121
   * @return 2 raised into given power
   */
  function pow_2 (uint128 x)
  public pure returns (bool, uint128) {
    return (
      true,
      YieldMath.pow_2 (x));
  }
}