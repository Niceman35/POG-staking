//SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract POGBox is Ownable {
    using EnumerableSet for EnumerableSet.UintSet;

    uint32 private constant MAX_LOCK_PERIOD = 365 days;
    uint32 public FeePeriod = 24 hours;
    uint32 public ClaimFee = 200; // 2%
    address public TREASURY;
    IERC20 public immutable POGToken;
    IERC1155 public immutable POGNFT;
    uint256 public TotalStaked;

    struct Stake {
        uint184 item;
        uint16 amount;
        uint24 claimed;
        uint32 stakeTime;
    }
    uint internal lastStakeID;
    mapping(uint => Stake) private allStakes;

    mapping(address => EnumerableSet.UintSet) private allUsers;

    struct Item {
        bool active;
        uint32 nftID;
        uint32 lockPeriod;
        uint80 stakePrice;
        uint80 openPrice;
    }
    Item[] internal allItems;



    event Staked(address indexed user, uint indexed item, uint amount, uint payment, uint indexed stakeId);
    event Claimed(address indexed user, uint indexed item, uint amount, uint payment, uint indexed stakeId);
    event Open(address indexed user, address receiver, uint item, uint amount, uint payment);
    event AddItem(uint item, uint lockPeriod, uint stakePrice, uint openPrice);
    event DeactivateItem(uint item);

    constructor(address _owner, address _treasury, IERC20 _pog, IERC1155 _pognft) {
        transferOwnership(_owner);
        TREASURY = _treasury;
        POGToken = _pog;
        POGNFT = _pognft;
    }

    function stake(uint _item, uint _amount) public {
        Item memory item = allItems[_item];
        require(item.active, "POGBox: inactive item");
        require(_amount > 0 && _amount < 1000, "POGBox: max 1000 boxes");
        uint payment = item.stakePrice * _amount;
        POGToken.transferFrom(_msgSender(), address(this), payment);
        TotalStaked += payment;

        uint stakeId = lastStakeID++;
        allStakes[stakeId] = Stake(uint184(_item), uint16(_amount), uint24(0), uint32(block.timestamp));
        allUsers[_msgSender()].add(stakeId);
        emit Staked(_msgSender(), _item, _amount, payment, stakeId);
    }

    function withdraw(uint[] calldata _stakes) public {
        for (uint i; i < _stakes.length; i++) {
            require(allUsers[_msgSender()].contains(_stakes[i]), "POGBox: stake not found");
            require(allStakes[_stakes[i]].stakeTime > 0, "POGBox: invalid stake id");
            require(_withdraw(_stakes[i], _msgSender()), "POGBox: error in withdraw");
        }
    }

    function claim(uint[] calldata _stakes) public {
        for (uint i; i < _stakes.length; i++) {
            require(allUsers[_msgSender()].contains(_stakes[i]), "POGBox: stake not found");
            require(allStakes[_stakes[i]].stakeTime > 0, "POGBox: invalid stake id");
            Stake storage _stake = allStakes[_stakes[i]];
            Item storage _item = allItems[_stake.item];
            if(_item.active) {
                uint boxesNum = _getBoxesNum(_stake, _item.lockPeriod);
                if(boxesNum > 0) {
                    _stake.claimed += uint16(boxesNum);
                    POGNFT.mint(_msgSender(), _item.nftID, boxesNum, "");
                }
            }
        }
    }

    function _withdraw(uint stakeId, address user) internal returns(bool) {
        Stake storage _stake = allStakes[stakeId];
        Item storage _item = allItems[_stake.item];
        uint payment = _item.stakePrice * _stake.amount;
        TotalStaked -= payment;
        uint fee;
        if(block.timestamp < _stake.stakeTime + FeePeriod) {
            fee = payment * ClaimFee / 10000;
            payment = payment - fee;
            require(fee > 0 && payment > fee, "calc error");
            POGToken.transfer(TREASURY, fee);
        }
        uint boxesNum;
        if(_item.active) {
            boxesNum = _getBoxesNum(_stake, _item.lockPeriod);
            if(boxesNum > 0) {
                _stake.claimed += uint16(boxesNum);
                POGNFT.mint(user, _item.nftID, boxesNum, "");
            }
        }
        POGToken.transfer(user, payment);

        if(allUsers[_msgSender()].remove(stakeId)) {
            delete allStakes[stakeId];
            emit Claimed(user, _stake.item, boxesNum, payment, stakeId);
            return true;
        } else {
            return false;
        }
    }

    function _getBoxesNum(Stake storage _stake, uint32 lockPeriod) internal view returns(uint256) {
        if(block.timestamp > _stake.stakeTime + lockPeriod) {
            uint256 boxesNum;
            boxesNum = ((block.timestamp - _stake.stakeTime) / lockPeriod) * _stake.amount;
            boxesNum -= _stake.claimed;
            require(boxesNum > 0, "calc error");
            return boxesNum;
        }
        return 0;
    }

    function open(uint _item, uint _amount, address _to) external {
        require(allItems[_item].lockPeriod > 0, "POGBox: invalid item");
        require(_to != address(0), "POGBox: wrong address provided");
        require(_open(_msgSender(), _to, _item, _amount, allItems[_item].openPrice), "POGBox: open box error");
    }

    function _open(address _from, address _to, uint _item, uint _amount, uint _price) internal returns(bool) {
        uint payment = _amount * _price;
        if (payment > 0) {
            POGToken.transferFrom(_from, TREASURY, payment);
        }
        POGNFT.burn(_from, allItems[_item].nftID, _amount);
        emit Open(_from, _to, allItems[_item].nftID, _amount, payment);
        return true;
    }

    function getStakeIds(address _user) public view returns(uint[] memory) {
        return allUsers[_user].values();
    }

    function getStakes(address _user) external view returns(Stake[] memory) {
        uint[] memory stakeIds = getStakeIds(_user);
        Stake[] memory stakes = new Stake[](stakeIds.length);
        for (uint i; i < stakeIds.length; i++) {
            stakes[i] = allStakes[stakeIds[i]];
        }
        return stakes;
    }

    //     Admin functions

    function addItem(uint _nftId, uint _lockPeriod, uint _stakePrice, uint _openPrice) external onlyOwner {
        require(_lockPeriod > 0 && _lockPeriod <= MAX_LOCK_PERIOD, "POGBox: invalid lock period");
        require(_stakePrice > 0, "POGBox: invalid stake price");
        allItems.push(Item(true, uint32(_nftId), uint32(_lockPeriod), uint80(_stakePrice), uint80(_openPrice)));
        emit AddItem(allItems.length, _lockPeriod, _stakePrice, _openPrice);
    }

    function deactivateItem(uint _item) external onlyOwner {
        require(allItems[_item].active, "POGBox: item is not active");
        allItems[_item].active = false;
        emit DeactivateItem(_item);
    }

    function getItems() external view returns(Item[] memory) {
        return allItems;
    }

    function getItem(uint _item) external view returns(Item memory) {
        Item memory item = allItems[_item];
        require(item.lockPeriod > 0, "POGBox: invalid item");
        return item;
    }

    /// Initialize boxes finction (4 boxes  5-4-2-3)

    function setTreasury(address _treasury) external onlyOwner {
        require(_treasury != address(0), "POGBox: wrong address");
        TREASURY = _treasury;
    }

    function setFee(uint32 _claimFee, uint32 _feePeriod) external onlyOwner {
        require(_claimFee > 0 && _feePeriod > 0, "POGBox: wrong data");
        FeePeriod = _feePeriod;
        ClaimFee = _claimFee;
    }


    // emergency balance recover functions

    function recoverBNB() external onlyOwner {
        payable(TREASURY).transfer(address(this).balance);
    }

    function recoverERC20(IERC20 _token) external onlyOwner {
        uint amount = _token.balanceOf(address(this));
        if(_token == POGToken) {
            amount -= TotalStaked;
        }
        require(amount > 0, "POGBox: Zero amount");
        _token.transfer(TREASURY, amount);
    }

    function recoverERC1155(IERC1155 _token, uint _item) external onlyOwner {
        _token.safeTransferFrom(address(this), TREASURY, _item, _token.balanceOf(address(this), _item), "");
    }
}

interface IERC1155 {
    function balanceOf(address account, uint256 id) external view returns (uint256);
    function mint(address to, uint256 id, uint256 amount, bytes memory data) external;
    function burn(address from, uint256 id, uint256 value) external;
    function safeTransferFrom(address from, address to, uint256 id, uint256 amount, bytes calldata data) external;
}

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
}
