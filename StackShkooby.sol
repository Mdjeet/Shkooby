// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./interfaces/IERC20.sol";
import "./store.sol";

contract stackShkooby is store, AccessControl, ReentrancyGuard {
    using Address for address;
    using SafeMath for uint256;

    address public immutable shkoobyToken;
    address public immutable shkoobyLpToken;
    address public Owner;

    constructor(address _shkoobyToken, address _shkoobyLpToken) {
        APR[0] = 10;
        APR[30] = 25;
        APR[90] = 50;
        APR[180] = 75;
        Owner = msg.sender;
        SHKOOBY_PER_ETH = 2500;
        shkoobyToken = _shkoobyToken;
        shkoobyLpToken = _shkoobyLpToken;
        _grantRole(EXTRACTOR, msg.sender);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    modifier onlyOwner() {
        require(msg.sender == Owner, "Shkooby-Stake: Not Owner");
        _;
    }

    modifier validateToken(address _tokenAddress) {
        require(
            shkoobyToken == _tokenAddress || shkoobyLpToken == _tokenAddress,
            "Shkooby-Stake: Invalid token address"
        );
        _;
    }

    function addExtractor(
        address _account
    ) public onlyRole(DEFAULT_ADMIN_ROLE) returns (bool) {
        _grantRole(EXTRACTOR, _account);
        return true;
    }

    function changeShkoobyPerEth(
        uint256 _amount
    ) public onlyOwner returns (uint256) {
        SHKOOBY_PER_ETH = _amount;
        return SHKOOBY_PER_ETH;
    }

    function calculateTransferValue(
        uint256 _amount
    ) public view returns (uint256 transferAmount) {
        transferAmount = SHKOOBY_PER_ETH.mul(_amount);
    }

    function getShkoobyForEth() public payable nonReentrant returns (uint256) {
        require(msg.value > 0, "Shkooby-Stake: Ether amount can't be zero");
        uint256 transferAmount = calculateTransferValue(msg.value);
        IERC20(shkoobyToken).mint(msg.sender, transferAmount);
        emit Exchange(transferAmount);
        return transferAmount;
    }

    function _calculateReward(
        address _address,
        address _tokenAddress,
        uint256 _index
    ) internal view returns (uint256 _reward) {
        Stack[] memory currentStake = stakes[_address][_tokenAddress];
        uint256 elapsedTime = block.timestamp - currentStake[_index].addTime;
        uint256 principleAmount = currentStake[_index].amount;
        uint256 reward = principleAmount
            .mul(currentStake[_index].apr)
            .mul(elapsedTime)
            .div(SECONDS_PER_YEAR);
        _reward = reward.sub(currentStake[_index].reward);
    }

    function calculateReward(
        address _account,
        address _tokenAddress,
        uint256 _index
    ) public view returns (uint256) {
        return _calculateReward(_account, _tokenAddress, _index);
    }

    function stake(
        address _tokenAddress,
        uint256 _amount,
        uint256 _timePeriod
    ) public validateToken(_tokenAddress) {
        require(_amount > 0, "Shkooby-Stake: Amount can't be 0");
        require(
            block.timestamp + _timePeriod >= block.timestamp,
            "Shkooby-Stake: inappropriate time period"
        );

        if (_tokenAddress == shkoobyToken) {
            IERC20(shkoobyToken).transferFrom(
                msg.sender,
                address(this),
                _amount
            );
            totalSupply = totalSupply.add(_amount);
        } else {
            IERC20(shkoobyLpToken).transferFrom(
                msg.sender,
                address(this),
                _amount
            );
            totalSupplyLp = totalSupplyLp.add(_amount);
        }

        stakes[msg.sender][_tokenAddress].push(
            Stack({
                amount: _amount,
                addTime: block.timestamp,
                tokenAddress: _tokenAddress,
                apr: APR[_timePeriod.div(SECONDS_PER_DAY)],
                releaseTime: block.timestamp.add(_timePeriod),
                reward: 0
            })
        );
        addCumulativeStackAmount(msg.sender, _tokenAddress, _amount);
        emit NewStake(
            _amount,
            block.timestamp,
            _tokenAddress,
            APR[_timePeriod.div(SECONDS_PER_DAY)],
            block.timestamp.add(_timePeriod)
        );
        return;
    }

    function claim(
        address _tokenAddress,
        uint256 _index
    ) public validateToken(_tokenAddress) {
        require(
            stakes[msg.sender][_tokenAddress].length > 0 &&
                _index <= stakes[msg.sender][_tokenAddress].length,
            "Shkooby-Stake: Nothing to claim"
        );
        uint256 claimAmount = calculateReward(
            msg.sender,
            _tokenAddress,
            _index
        );
        stakes[msg.sender][_tokenAddress][_index].reward += claimAmount;
        claims[msg.sender][_tokenAddress].push(
            Stack({
                amount: 0,
                addTime: block.timestamp,
                tokenAddress: _tokenAddress,
                apr: 0,
                releaseTime: block.timestamp.add(SECONDS_PER_YEAR),
                reward: claimAmount
            })
        );
        addCummulativeClaimAmount(msg.sender, _tokenAddress, claimAmount);
    }

    function redeemTokens(
        address _tokenAddress,
        uint256 _index
    ) public validateToken(_tokenAddress) {
        Stack[] memory currentClaim = claims[msg.sender][_tokenAddress];
        require(
            currentClaim.length > 0 && _index <= currentClaim.length,
            "Shkooby-Stake: Nothing to redeem"
        );

        require(
            currentClaim[_index].releaseTime <= block.timestamp,
            "Shkooby-Stake: Can't redeem before timeperiod"
        );

        // We can either transfer or mint that much amount to user
        // here we have transfered from this contract
        require(
            currentClaim[_index].amount <=
                IERC20(_tokenAddress).balanceOf(address(this)),
            "Shkooby-Stake: Insufficient pool balance"
        );
        IERC20(_tokenAddress).transfer(msg.sender, currentClaim[_index].amount);
        delete claims[msg.sender][_tokenAddress][_index];
        claims[msg.sender][_tokenAddress][_index] = currentClaim[
            currentClaim.length - 1
        ];
        claims[msg.sender][_tokenAddress].pop();
    }

    function withdrawPrinciple(
        address _tokenAddress,
        uint256 _index
    ) public validateToken(_tokenAddress) nonReentrant {
        Stack[] memory currentStake = stakes[msg.sender][_tokenAddress];

        require(
            _index <= currentStake.length && currentStake.length > 0,
            "Shkooby-Stake: Invalid index"
        );
        require(
            currentStake[_index].releaseTime <= block.timestamp,
            "Shkooby-Stake: Can't withdraw before release time"
        );
        claim(_tokenAddress, _index);
        uint256 deductAmount = currentStake[_index].amount;
        require(
            deductAmount <= IERC20(_tokenAddress).balanceOf(address(this)),
            "Shkooby-Stake: Insufficient pool balance"
        );

        if (_tokenAddress == shkoobyToken) {
            IERC20(shkoobyToken).transfer(msg.sender, deductAmount);
            totalSupply = totalSupply.sub(deductAmount);
        } else {
            IERC20(shkoobyLpToken).transfer(msg.sender, deductAmount);
            totalSupplyLp = totalSupplyLp.add(deductAmount);
        }

        delete stakes[msg.sender][_tokenAddress][_index];
        stakes[msg.sender][_tokenAddress][_index] = stakes[msg.sender][
            _tokenAddress
        ][currentStake.length - 1];
        stakes[msg.sender][_tokenAddress].pop();
        emit Withdrwal(_index, _tokenAddress, deductAmount);
        deductCummulativeStakeAmount(msg.sender, _tokenAddress, deductAmount);
    }

    function getStake(
        address _account,
        address _tokenAddress,
        uint256 _index
    ) public view returns (Stack memory) {
        uint256 rewardAmount = calculateReward(_account, _tokenAddress, _index);
        Stack memory currStake = stakes[_account][_tokenAddress][_index];
        currStake.reward = rewardAmount;
        return currStake;
    }

    function getClaim(
        address _account,
        address _tokenAddress,
        uint256 _index
    ) public view returns (Stack memory) {
        return claims[_account][_tokenAddress][_index];
    }

    function transferEth(
        address payable _to
    ) public payable onlyRole(EXTRACTOR) {
        uint256 currBalance = address(this).balance;
        _to.transfer(currBalance);
    }
}
