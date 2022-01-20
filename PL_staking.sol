//SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import "@openzeppelin/contracts/access/Ownable.sol";

contract POGLPStaking is Ownable {

    uint32 public FeePeriod = 7 days;
    uint32 public ClaimFee = 200; // 2%
    uint32 public minAmount = 500;
    address public TREASURY;
    IERC20 public immutable LPToken;
    uint256 public TotalStaked;

    struct Stake {
        uint224 amount;
        uint32 stakeTime;
    }

    mapping(address => Stake) internal AllStakes;

    event Staked(address indexed user, uint256 amount);
    event Claimed(address indexed user, uint256 amount, uint256 fee);
    event FeeSet(uint256 period, uint256 fee);
    event MinAmountSet(uint32 newMinAmount);

    constructor(address _owner, IERC20 _lpToken, address _treasury) {
        transferOwnership(_owner);
        LPToken = _lpToken;
        TREASURY = _treasury;
    }

    function stake(uint256 _amount) public {
        Stake storage userStake = AllStakes[_msgSender()];
        uint224 amount = uint224(_amount);
        require(amount > 0, "POGLPStake: wrong amount");
        uint224 newAmount = userStake.amount + amount;
        require(newAmount >= uint224(minAmount) * 1 ether, "POGLPStake: cannot stake less than min");

        userStake.amount = newAmount;
        userStake.stakeTime = uint32(block.timestamp);
        TotalStaked += amount;
        LPToken.transferFrom(_msgSender(), address(this), amount);
        emit Staked(_msgSender(), amount);
    }

    function claim(uint256 _amount) public {
        Stake storage userStake = AllStakes[_msgSender()];
        uint224 amount = uint224(_amount);
        require(amount > 0, "POGLPStake: wrong amount");
        require(amount <= userStake.amount, "POGLPStake: balance not enough");
        userStake.amount -= amount;
        TotalStaked -= amount;
        uint224 fee;
        if(block.timestamp < userStake.stakeTime + FeePeriod) {
            fee = amount * ClaimFee / 10000;
            amount = amount - fee;
            require(fee > 0 && amount > fee, "calc error");
            LPToken.transfer(TREASURY, fee);
        }
        LPToken.transfer(_msgSender(), amount);
        emit Claimed(_msgSender(), amount, fee);
    }

    function getStake(address _user) external view returns(Stake memory) {
        return AllStakes[_user];
    }

    //     Admin functions

    function setFee(uint32 _claimFee, uint32 _feePeriod) external onlyOwner {
        require(_claimFee > 0 && _feePeriod > 0, "POGBox: wrong data");
        FeePeriod = _feePeriod;
        ClaimFee = _claimFee;
        emit FeeSet(_feePeriod, _claimFee);
    }

    function setTreasury(address _treasury) external onlyOwner {
        require(_treasury != address(0), "POGBox: wrong address");
        TREASURY = _treasury;
    }

    function setMinAmount(uint32 _newMinAmount) external onlyOwner {
        require(_newMinAmount > 0, "POGLPStake: min amount cannot be 0");
        minAmount = _newMinAmount;
        emit MinAmountSet(minAmount);
    }

    // emergency balance recover functions

    function recoverBNB() external onlyOwner {
        payable(TREASURY).transfer(address(this).balance);
    }

    function recoverERC20(IERC20 _token) external onlyOwner {
        uint amount = _token.balanceOf(address(this));
        if(_token == LPToken) {
            amount -= TotalStaked;
        }
        require(amount > 0, "POGLPStake: Zero amount");
        _token.transfer(TREASURY, _token.balanceOf(address(this)));
    }
}

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
}