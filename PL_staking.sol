//SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import "@openzeppelin/contracts/access/Ownable.sol";

contract IslandStaking is Ownable {
    uint32 public FeePeriod = 7 days;
    uint32 public ClaimFee = 2; // 2%
    uint32 public MinAmount = 500; // min 500 lp/POG tokens
    address public Treasury; // set in constructor
    uint256 public TotalStaked;
    IERC20 public immutable Token;  // set in constructor

    struct StakeStruct {
        uint224 amount;
        uint32 stakeTime;
    }

    mapping(address => StakeStruct) internal AllStakes;

    event Stake(address indexed user, uint256 amount);
    event Claim(address indexed user, uint256 amount, uint256 fee);
    event SetFee(uint256 period, uint256 fee);
    event SetMinAmount(uint32 newMinAmount);

    constructor(address _owner) {
        transferOwnership(_owner);
        Token = IERC20(0x56830e12976DfDfFcd3c6Ac29Ac4E603377A5002); //Set token address here
        Treasury = payable(0xc711A44078E11c5bB5c0ce12caA9c212C9c65BD2);
    }

    function stake(uint256 _amount) public {
        StakeStruct storage userStake = AllStakes[_msgSender()];
        uint224 amount = uint224(_amount);
        require(amount > 0, "wrong amount");
        userStake.amount += amount;
        require(userStake.amount >= uint224(MinAmount) * 1 ether, "cannot stake less than min");
        userStake.stakeTime = uint32(block.timestamp);
        TotalStaked += amount;
        Token.transferFrom(_msgSender(), address(this), amount);
        emit Stake(_msgSender(), amount);
    }

    function claim(uint256 _amount) public {
        StakeStruct storage userStake = AllStakes[_msgSender()];
        uint224 amount = uint224(_amount);
        require(amount > 0, "wrong amount");
        require(amount <= userStake.amount, "balance not enough");
        userStake.amount -= amount;
        TotalStaked -= amount;
        uint224 fee;
        if(block.timestamp < userStake.stakeTime + FeePeriod) {
            fee = amount * ClaimFee / 100;
            amount = amount - fee;
            require(fee > 0 && amount > fee, "calc error");
            Token.transfer(Treasury, fee);
        }
        Token.transfer(_msgSender(), amount);
        emit Claim(_msgSender(), amount, fee);
    }

    function getStake(address _user) external view returns(StakeStruct memory) {
        return AllStakes[_user];
    }

    //  Admin functions

    function setFee(uint32 _claimFee, uint32 _feePeriod) external onlyOwner {
        require(_claimFee > 0 && _feePeriod > 0, "wrong data");
        FeePeriod = _feePeriod;
        ClaimFee = _claimFee;
        emit SetFee(_feePeriod, _claimFee);
    }

    function setTreasury(address _treasury) external onlyOwner {
        require(_treasury != address(0), "wrong address");
        Treasury = _treasury;
    }

    function setMinAmount(uint32 _newMinAmount) external onlyOwner {
        require(_newMinAmount > 0, "min amount cannot be 0");
        MinAmount = _newMinAmount;
        emit SetMinAmount(MinAmount);
    }

    // emergency balance recover functions

    function recoverBNB() external onlyOwner {
        payable(Treasury).transfer(address(this).balance);
    }

    function recoverERC20(IERC20 _token) external onlyOwner {
        uint amount = _token.balanceOf(address(this));
        if(_token == Token) {
            amount -= TotalStaked;
        }
        require(amount > 0, "zero amount");
        _token.transfer(Treasury, amount);
    }
}

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
}