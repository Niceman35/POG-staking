//SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract ItemStaking is Ownable {
    using EnumerableSet for EnumerableSet.UintSet;

    uint32 public FeePeriod = 24 hours;
    uint32 public ClaimFee = 2; // 2%
    address public Treasure; // set in constructor
    IERC20 public immutable POGToken; // set in constructor
    IERC1155 public immutable POGNFT; // set in constructor
    uint128 public TotalStaked;
    uint128 internal lastStakeID;
    ItemStruct[] internal allItems;

    mapping(uint256 => StakeStruct) private allStakes; // StakeStruct database
    mapping(address => EnumerableSet.UintSet) private allUsers; // StakeStruct database indexes linked to user

    struct StakeStruct {
        uint184 item;
        uint16 amount;
        uint24 claimed;
        uint32 stakeTime;
    }
    struct ItemStruct {
        bool active;
        uint32 nftID;
        uint32 lockPeriod;
        uint80 stakePrice;
        uint80 openPrice;
    }

    // Events list

    event Stake(
        address indexed user,
        uint256 indexed item,
        uint256 amount,
        uint256 payment,
        uint256 indexed stakeId
    );
    event Claim(
        address indexed user,
        uint256 indexed item,
        uint256 nftID,
        uint256 count,
        uint256 indexed stakeId
    );
    event Withdraw(
        address indexed user,
        uint256 indexed item,
        uint256 payment,
        uint256 fee,
        uint256 indexed stakeId
    );
    event Open(
        address indexed user,
        address receiver,
        uint256 indexed item,
        uint256 indexed nftID,
        uint256 count,
        uint256 payment
    );
    event CreateItem(
        uint256 item,
        uint256 lockPeriod,
        uint256 stakePrice,
        uint256 openPrice
    );
    event DeactivateItem(
        uint256 item
    );
    event ActivateItem(
        uint256 item
    );

    constructor(address owner) {
        transferOwnership(owner);
        //        POGToken = IERC20(0xFCb0f2D2f83a32A847D8ABb183B724C214CD7dD8);
        POGToken = IERC20(0x8985420180ACD9320B3808D688240DA23c43f39e); // TestNet
        //        POGNFT = IERC1155(0xC1c8F100c9Eff87c7C1e99a266b670FE4486dd17);
        POGNFT = IERC1155(0xeD275A14023dC979f15fe9493eadfB8045747415); // TestNet
        Treasure = payable(0xc711A44078E11c5bB5c0ce12caA9c212C9c65BD2);
        allItems.push(ItemStruct(true, 5, 14 days, 250 ether, 2.5 ether));
        allItems.push(ItemStruct(true, 4, 14 days, 500 ether, 5 ether));
        allItems.push(ItemStruct(true, 2, 14 days, 1000 ether, 10 ether));
        allItems.push(ItemStruct(true, 3, 14 days, 1500 ether, 15 ether));
    }

    function stake(uint16 _item, uint16 _amount) public {
        ItemStruct storage item = allItems[_item];
        require(item.active, "inactive item");
        require(_amount > 0 && _amount < 1000, "max 1000 boxes");
        uint128 payment = item.stakePrice * _amount;
        POGToken.transferFrom(_msgSender(), address(this), payment);
        TotalStaked += payment;

        uint256 stakeId = lastStakeID++;
        allStakes[stakeId] = StakeStruct(
            uint184(_item),
            uint16(_amount),
            uint24(0),
            uint32(block.timestamp)
        );
        allUsers[_msgSender()].add(stakeId);
        emit Stake(_msgSender(), _item, _amount, payment, stakeId);
    }

    // withdraw all: box + token

    function withdraw(uint256[] calldata _stakes) external {
        for (uint256 i; i < _stakes.length; i++) {
            require(
                allUsers[_msgSender()].contains(_stakes[i]),
                "stake not found"
            );
            require(
                allStakes[_stakes[i]].stakeTime > 0,
                "invalid stake id"
            );
            _claimBox(_stakes[i], _msgSender());
            _withdrawPOG(_stakes[i], _msgSender());
            require(
                allUsers[_msgSender()].remove(_stakes[i]),
                "error in withdraw"
            );
            delete allStakes[_stakes[i]];
        }
    }

    // withdraw: box only

    function claim(uint256[] calldata _stakes) external {
        for (uint256 i; i < _stakes.length; i++) {
            require(
                allUsers[_msgSender()].contains(_stakes[i]),
                "stake not found"
            );
            require(
                allStakes[_stakes[i]].stakeTime > 0,
                "invalid stake"
            );
            _claimBox(_stakes[i], _msgSender());
        }
    }

    function open(
        uint256 _item,
        uint256 _count,
        address _to
    ) external {
        require(allItems[_item].openPrice > 0, "invalid item");
        require(_count > 0, "amount should be positive");
        require(_to != address(0), "wrong address provided");
        uint256 payment = _count * allItems[_item].openPrice;
        POGToken.transferFrom(_msgSender(), Treasure, payment);
        POGNFT.burn(_msgSender(), allItems[_item].nftID, _count);
        emit Open(_msgSender(), _to, _item, allItems[_item].nftID, _count, payment);
    }

    // helper for withdraw

    function _withdrawPOG(uint256 stakeId, address user) internal {
        StakeStruct storage _stake = allStakes[stakeId];
        ItemStruct storage _item = allItems[_stake.item];
        uint128 payment = _item.stakePrice * _stake.amount;
        uint128 fee;
        if (block.timestamp < _stake.stakeTime + FeePeriod) {
            fee = payment * ClaimFee / 100;
            payment -= fee;
            POGToken.transfer(Treasure, fee);
        }
        TotalStaked -= payment;
        POGToken.transfer(user, payment);
        emit Withdraw(user, _stake.item, payment, fee, stakeId);
    }

    // helper for claim box

    function _claimBox(uint256 stakeId, address user) internal {
        StakeStruct storage _stake = allStakes[stakeId];
        ItemStruct storage _item = allItems[_stake.item];
        if (_item.active && block.timestamp > _stake.stakeTime + _item.lockPeriod) {
            uint256 boxesNum;
            boxesNum = ((block.timestamp - _stake.stakeTime) / _item.lockPeriod) *  _stake.amount;
            boxesNum -= _stake.claimed;
            _stake.claimed += uint16(boxesNum);
            POGNFT.mint(user, _item.nftID, boxesNum, "");
            emit Claim(user, _stake.item, _item.nftID, boxesNum, stakeId);
        }
    }

    /*
    return IDs of staked boxes
    @returns {Array} => [0,1,2,3]
    */

    function getStakeIds(address _user) public view returns (uint256[] memory) {
        return allUsers[_user].values();
    }

    /*
    returns active box stakes
    @returns [Array] => [Stake { uint184 item; uint16 amount; uint24 claimed; uint32 stakeTime; }]
    */

    function getStakes(address _user) public view returns (StakeStruct[] memory) {
        uint256[] memory stakeIds = getStakeIds(_user);
        StakeStruct[] memory stakes = new StakeStruct[](stakeIds.length);
        for (uint256 i; i < stakeIds.length; i++) {
            stakes[i] = allStakes[stakeIds[i]];
        }
        return stakes;
    }

    function getItems() public view returns (ItemStruct[] memory) {
        return allItems;
    }

    function getItem(uint256 _item) public view returns (ItemStruct memory) {
        ItemStruct memory item = allItems[_item];
        require(item.lockPeriod > 0, "invalid item");
        return item;
    }

    //     Admin functions

    function createItem(
        uint256 _nftId,
        uint256 _lockPeriod,
        uint256 _stakePrice,
        uint256 _openPrice
    ) external onlyOwner {
        require(_lockPeriod > 0 && _stakePrice > 0, "invalid input data");
        allItems.push(
            ItemStruct(
                true,
                uint32(_nftId),
                uint32(_lockPeriod),
                uint80(_stakePrice),
                uint80(_openPrice)
            )
        );
        emit CreateItem((allItems.length - 1), _lockPeriod, _stakePrice, _openPrice);
    }

    function deactivateItem(uint256 _item) external onlyOwner {
        require(allItems[_item].active, "item is not active");
        allItems[_item].active = false;
        emit DeactivateItem(_item);
    }

    function activateItem(uint256 _item) external onlyOwner {
        require(!allItems[_item].active, "item is active");
        allItems[_item].active = true;
        emit ActivateItem(_item);
    }

    function setTreasury(address _treasury) external onlyOwner {
        require(_treasury != address(0), "wrong address");
        Treasure = _treasury;
    }

    function setFee(uint32 _claimFee, uint32 _feePeriod) external onlyOwner {
        require(_claimFee > 0 && _feePeriod > 0, "wrong data");
        FeePeriod = _feePeriod;
        ClaimFee = _claimFee;
    }

    // emergency balance recover functions

    function recoverBNB() external onlyOwner {
        payable(Treasure).transfer(address(this).balance);
    }

    function recoverERC20(IERC20 _token) external onlyOwner {
        uint256 amount = _token.balanceOf(address(this));

        // Not allows to withdraw staked POGs (only not staked properly POGs will be withdrawn)
        if (_token == POGToken) {
            amount -= TotalStaked;
        }
        require(amount > 0, "Zero amount");
        _token.transfer(Treasure, amount);
    }

    function recoverERC1155(IERC1155 _token, uint256 _item) external onlyOwner {
        _token.safeTransferFrom(
            address(this),
            Treasure,
            _item,
            _token.balanceOf(address(this), _item),
            ""
        );
    }
}

interface IERC1155 {
    function balanceOf(address account, uint256 id)
    external
    view
    returns (uint256);

    function mint(
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) external;

    function burn(
        address from,
        uint256 id,
        uint256 value
    ) external;

    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes calldata data
    ) external;
}

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);

    function transfer(address recipient, uint256 amount)
    external
    returns (bool);

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);
}