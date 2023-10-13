// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract store {
    using SafeMath for uint256;

    bytes32 public constant EXTRACTOR = keccak256("ETH_EXTRACTOR_ROLE");

    uint256 internal constant SECONDS_PER_YEAR = 365 days;
    uint256 internal constant SECONDS_PER_DAY = 1 days;
    uint256 public SHKOOBY_PER_ETH;

    uint256 public totalSupply;
    uint256 public totalSupplyLp;

    uint256 rewardTokenPerSec;
    uint256 rewardTokenPerSecLp;

    struct Stack {
        uint256 amount;
        uint256 addTime;
        address tokenAddress;
        uint256 apr;
        uint256 releaseTime;
        uint256 reward;
    }
    mapping(uint => uint) public APR;
    mapping(address => mapping(address => uint)) public totalAmountStack;
    mapping(address => mapping(address => uint)) public totalRewadClaimed;
    mapping(address => mapping(address => Stack[])) internal stakes;
    mapping(address => mapping(address => Stack[])) internal claims;

    event Exchange(uint256 Shkooby);
    event NewStake(
        uint256 amount,
        uint256 stakeTime,
        address tokenAddress,
        uint256 apr,
        uint256 releaseTime
    );
    event Withdrwal(uint256 index, address token, uint256 amount);

    function addCumulativeStackAmount(
        address _account,
        address _token,
        uint256 _amount
    ) internal returns (uint256) {
        return totalAmountStack[_account][_token] += _amount;
    }

    function addCummulativeClaimAmount(
        address _account,
        address _token,
        uint256 _amount
    ) internal returns (uint256) {
        return totalRewadClaimed[_account][_token] += _amount;
    }

    function deductCummulativeStakeAmount(
        address _account,
        address _token,
        uint256 _amount
    ) internal returns (uint256) {
        return totalAmountStack[_account][_token] -= _amount;
    }

    function getStakesLength(
        address _account,
        address _token
    ) public view returns (uint256) {
        return stakes[_account][_token].length;
    }

    function getClaimsLength(
        address _account,
        address _token
    ) public view returns (uint256) {
        return claims[_account][_token].length;
    }
}
