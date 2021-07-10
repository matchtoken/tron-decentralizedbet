// SPDX-License-Identifier: MIT
pragma solidity ^0.5.17;

import "./SafeMath.sol";
import "./ITRC20.sol";

/* 
   [̲̅S][̲̅O][̲̅C][̲̅C][̲̅E][̲̅R][̲̅C][̲̅R][̲̅Y][̲̅P][̲̅T]
   
   &

   𝕄𝕒𝕥𝕔𝕙 𝕋𝕠𝕜𝕖𝕟 𝕋𝕖𝕒𝕞

*/

contract Owner {
    address public owner;

    constructor() public {
        owner = msg.sender;
    }

    modifier onlyOwner {
        require(msg.sender == owner);
        _;
    }

    event OwnershipTransferred(address indexed previousOwner,address indexed newOwner);

    function transferOwnership(address newOwner) onlyOwner public {
        require(newOwner != address(0x0),"Cannot zero address");
        address oldOwner = owner;
        owner = newOwner;
        emit OwnershipTransferred(oldOwner,owner);
    }
}

/// @author Soccercrypt & MATCH team
/// @title Decentralized Bet (de-bet)
contract DecentralizedBet is Owner{

  using SafeMath for uint256;
  using SafeMath64 for uint64;

  uint64 public MINIMUM_BET = 1000000;
  uint64 private constant PROVIDER_FEE = 300;
  uint64 private constant REFERRAL_FEE = 100;
  uint8 private constant MATCH_TOKEN_CODE = 100;
  uint8 private constant MAKER_WIN = 1;
  uint8 private constant TAKER_WIN = 2;
  uint8 private constant BOTH_WIN = 100;

  uint64 constant public DIVIDER = 10000;
  address public providerAddress = address(0x41620841a7d9b729b8b5904254b88cb32f4407989e) ; 
  address public refereeAddress = address(0x41620841a7d9b729b8b5904254b88cb32f4407989e) ; 
  
  address private constant matchContract = address(0x41e8558dd6776df8f635fc0b566b1c3074a2d07a25);
  mapping (uint256 => Order) internal orders;
  mapping (bytes32 => uint256[]) internal orderGroups;

  mapping(address => Reff) internal reffSystem;
  mapping(uint256 => Token) internal allowedTokens;

  struct Token{
    ITRC20 trc20;
    address _address;
  }
  struct Reff{
    address referrer;
    uint64 claimable;
  }
  struct Order{
    bool makerClaimed;
    bool takerClaimed;
    uint8 winner; 
    uint8 betType ;
    uint8 status; 
    uint16 valueBetType;
    uint32 odds; 
    uint32 startTime;
    uint64 matchId;
    uint64 orderId;
    uint64 makerPot; 
    uint64 makerTotalPot; 
    uint64 takerPot; 
    address makerSide;
    address takerSide;
    uint64 tokenCode;
    
  }

  
  constructor() public {

    addToken(matchContract,MATCH_TOKEN_CODE);
  }

  event Claimed(address indexed user, uint256 orderId, uint64 amount);
  event OrderCreated(bytes32 _groupId, uint64 _matchId, uint256 _orderId,uint256 createdTime);
  event MatchSettled(bytes32 _groupId);



  function recoverAddress(bytes memory abiEncoded, bytes memory signature) internal pure returns(address){

    bytes32 hashed = keccak256(abiEncoded);

    bytes32  r = convertToBytes32(slice(signature, 0, 32));
    bytes32  s = convertToBytes32(slice(signature, 32, 32));
    byte  v1 = slice(signature, 64, 1)[0];
    uint8 v = uint8(v1);
    address result = ecrecover(hashed, v,r,s);
    require(result != address(0x0),"Can't recover the address");
    return result;
  }

  function slice(bytes memory data, uint start, uint len) internal pure returns (bytes memory){
      bytes memory b = new bytes(len);
      for(uint i = 0; i < len; i++){
          b[i] = data[i + start];
      }
      return b;
  }

  function convertToBytes32(bytes memory source) internal pure returns (bytes32 result) {
      assembly {
          result := mload(add(source, 32))
      }
  }

  /// @notice Creating an order / betslip
  /// @param makerParams parameters of the maker. it will be 9-length array of uint64
  /// @param _orderId id for the betslip from the referee
  /// @param orderGroupId id for betslip that grouped by bet type
  /// @param _takerPot value of taker pot in the betslip
  /// @param makerSignature the signature of makerParams
  /// @param refereeSignature the signature from Referee that will protect the maker params, _orderId & orderGroupId
  /// @param referrer the taker's referrer
  /// @return status of the create order
  function createOrder(uint64[] memory makerParams,uint256 _orderId, bytes32 orderGroupId, uint64 _takerPot, bytes memory makerSignature,bytes memory refereeSignature,address referrer) public returns(bool){

    bytes memory prefix = "\x19TRON Signed Message:\n32";

    require(makerParams.length == 9 , "Invalid makerParams");
    require(allowedTokens[makerParams[8]]._address != address(0), "Invalid tokens");
    require(_orderId > 0 , "Invalid takerParams");
    require(_takerPot >= MINIMUM_BET,"Raise your bet!");

    bytes memory encoded = abi.encodePacked(prefix,makerParams);
    address addrMaker = recoverAddress(encoded,makerSignature);

    //require(addrMaker == maker,"Invalid maker");

    Order storage order = orders[_orderId];
    require(order.orderId == 0 , "Duplicate Order ID");

    order.matchId = makerParams[0];
    order.odds = uint32(makerParams[1]);
    order.startTime = uint32(makerParams[2]);
    order.makerTotalPot = makerParams[4];
    order.betType = uint8(makerParams[5]);
    order.status = 99;
    order.valueBetType = uint16(makerParams[6]);
    order.orderId = uint64(_orderId);
    order.takerPot = _takerPot;
    order.makerSide = addrMaker;
    order.tokenCode = makerParams[8];

    require(block.timestamp<= makerParams[7],"Maker order Expired");
    require(block.timestamp < makerParams[2],"The match already started");
    require(makerParams[2] < makerParams[3],"StartTime > EndTime");
    require(order.odds > 100,"Minimum Odds 101");

    //require(memOrder.makerSide!= msg.sender,"Maker == Taker"); //maker != taker

    encoded = abi.encodePacked(prefix,_orderId,orderGroupId,makerSignature);
    require(recoverAddress(encoded,refereeSignature) == refereeAddress, "Invalid Referee");
    order.takerSide = msg.sender;

    emit OrderCreated(orderGroupId,order.matchId,order.orderId,block.timestamp);
    uint64 makerTotalPotUsed = 0;
    uint makerOrdersLength = orderGroups[orderGroupId].length;
    for(uint i=0 ; i < makerOrdersLength ; i++){
      uint256 loopOrderId = orderGroups[orderGroupId][i];
      if(orders[loopOrderId].odds > 0){
        require(orders[loopOrderId].odds == order.odds,"Duplicate order on Maker Side for one Match!");
      }
      makerTotalPotUsed = makerTotalPotUsed.add(orders[loopOrderId].makerPot);
    }
    order.makerTotalPot = order.makerTotalPot.sub(makerTotalPotUsed);
    order.makerPot = uint64(order.odds).sub(100).mul(order.takerPot).div(100);
    require(order.makerPot<=order.makerTotalPot,"Maker Pot Limit Exceeded");

    ITRC20 trc20 = allowedTokens[order.tokenCode].trc20;
    require(trc20.allowance(order.makerSide,address(this))>=order.makerPot,"insufficient maker allowance");
    require(trc20.allowance(order.takerSide,address(this))>=order.takerPot,"insufficient taker allowance");

    require(trc20.balanceOf(order.makerSide)>=order.makerPot,"insufficient maker balance");
    require(trc20.balanceOf(order.takerSide)>=order.takerPot,"insufficient taker balance");

    trc20.transferFrom(order.makerSide,address(this),order.makerPot);
    trc20.transferFrom(order.takerSide,address(this),order.takerPot);


    order.status = 0;
    orderGroups[orderGroupId].push(order.orderId);


    if(reffSystem[msg.sender].referrer == address(0) && order.tokenCode == MATCH_TOKEN_CODE  ){
       if (referrer != providerAddress && referrer != msg.sender ){
        reffSystem[msg.sender].referrer = referrer;
      }
    }
   
    return true;
  }

  /// @notice to get referrer balance
  /// @param addr referrer's address
  /// @return claimable balance of referrer
  function getRefClaimable(address addr) public view returns(uint64){
    return reffSystem[addr].claimable;
  }

  /// @notice claim referral fee. only for match token
  function claimReferralFee() public{
    require(reffSystem[msg.sender].claimable > 0,"");
    require(allowedTokens[MATCH_TOKEN_CODE]._address != address(0), "Invalid tokens");
    uint64 claimable = reffSystem[msg.sender].claimable;
    reffSystem[msg.sender].claimable =0;
    allowedTokens[MATCH_TOKEN_CODE].trc20.transfer(msg.sender,claimable);
  
  }

  /// @notice get order information by id
  /// @param orderId identifier for the order
  /// @return 17-length array of uint256
  function getOrderById(uint64 orderId) public view returns(uint256[] memory rInt){
     Order memory order = orders[orderId];
     rInt = new uint256[](17);
     rInt[0] = uint256(order.orderId);
     rInt[1] = uint256(order.matchId);
     rInt[2] = uint256(order.odds);
     rInt[3] = uint256(order.takerSide);
     rInt[4] = uint256(order.makerSide);
     rInt[5] = uint256(order.makerPot);
     rInt[6] = uint256(order.makerTotalPot);
     rInt[7] = uint256(order.takerPot);
     rInt[8] = uint256(order.betType);
     rInt[9] = uint256(order.status);
     rInt[10] = uint256(order.valueBetType);
     rInt[11] = uint256(order.startTime);
     rInt[13] = order.makerClaimed?1:0;
     rInt[14] = order.takerClaimed?1:0;
     rInt[15] = uint256(order.winner);
     rInt[16] = uint256(order.tokenCode);
     return rInt;
  }

  /// @notice to get token that can be used in de-bet
  /// @param codeToken identifier for the token
  /// @return the address of the token
  function getAllowedTokens(uint256 codeToken) public view returns(address){
 
    return allowedTokens[codeToken]._address;
  }

  /// @notice to get list of order id by the group id
  /// @param groupId identifier of the group
  /// @return list of order id from the group
  function getOrderIdsByGroup(bytes32 groupId) public view returns(uint256[] memory){

    return orderGroups[groupId];

  }

  /// @notice to claim the win
  /// @param orderId identifier of the order
  /// @return status of the claim
  function claim(uint256 orderId) public returns(bool) {

    Order storage order = orders[orderId];
    require(order.status == 1 || order.status == BOTH_WIN,"Invalid Order");
    require(allowedTokens[order.tokenCode]._address != address(0), "Invalid token");
     ITRC20 trc20 = allowedTokens[order.tokenCode].trc20;
    if(order.status == 1){
      require(order.winner == MAKER_WIN || order.winner == TAKER_WIN ,"Invalid Winner");
      require(!order.makerClaimed && !order.takerClaimed,"Invalid Claim");
      if(order.winner == MAKER_WIN){
       require(order.makerSide == msg.sender,"Invalid Maker Side");
        uint64 pot = order.takerPot;
        uint64 fee = 0;
        if(allowedTokens[order.tokenCode]._address != matchContract){
          fee = pot.mul(PROVIDER_FEE).div(DIVIDER);
        }

        pot = pot.sub(fee).add(order.makerPot);

        if(reffSystem[order.takerSide].referrer != address(0) && fee > 0){
          uint64 rFee = fee.mul(REFERRAL_FEE).div(DIVIDER);
          fee = fee.sub(rFee);
          reffSystem[reffSystem[order.takerSide].referrer].claimable = reffSystem[reffSystem[order.takerSide].referrer].claimable.add(rFee);
        }

        if(fee>0){
          trc20.transfer(providerAddress,fee);
        }
        
        trc20.transfer(msg.sender,pot);
        emit Claimed(msg.sender, order.orderId, pot);
        order.makerClaimed=true;
        return true;

      }else if(order.winner == TAKER_WIN){
        require(order.takerSide == msg.sender,"Invalid Taker Side");
        uint64 pot = order.makerPot;
        uint64 fee = 0;
        if(allowedTokens[order.tokenCode]._address != matchContract){
          fee = pot.mul(PROVIDER_FEE).div(DIVIDER);
        }

        pot = pot.sub(fee).add(order.takerPot);
        if(reffSystem[order.takerSide].referrer != address(0) && fee > 0){
          uint64 rFee = fee.mul(REFERRAL_FEE).div(DIVIDER);
          fee = fee.sub(rFee);
          reffSystem[reffSystem[order.takerSide].referrer].claimable = reffSystem[reffSystem[order.takerSide].referrer].claimable.add(rFee);
        }

        if(fee>0){
          trc20.transfer(providerAddress,fee);
        }
        
        trc20.transfer(msg.sender,pot);
        emit Claimed(msg.sender,order.orderId, pot);
        order.takerClaimed=true;
        return true;

      }

    }else if (order.status == BOTH_WIN){
      require(order.winner == BOTH_WIN ,"Invalid Winner");
      if(order.makerSide == msg.sender){
        require(!order.makerClaimed ,"Invalid Maker Claim");
        trc20.transfer(msg.sender,order.makerPot);
        order.makerClaimed = true;
        emit Claimed(msg.sender,order.orderId, order.makerPot);
      }else if(order.takerSide == msg.sender){
        require(!order.takerClaimed,"Invalid Taker Claim");
        trc20.transfer(msg.sender,order.takerPot);
        order.takerClaimed = true;
        emit Claimed(msg.sender,order.orderId, order.takerPot);
        return true;
      }
    }
  }

  /// @notice setting result of the match
  /// @param winner set the winner side (taker or maker)
  /// @param groupId identifier of the group
  /// @return status of setting of the match result
  function setMatchResult(bool winner,bytes32 groupId) public returns(bool){

    require(msg.sender == refereeAddress,"Invalid requestor");

    uint256 length = orderGroups[groupId].length;

    require(length >0, "No Data for GroupId");
    for(uint256 i = 0 ; i < length ; i ++){
      Order storage order = orders[orderGroups[groupId][i]];

      require(order.matchId>0,"invalid order");
      require(order.status == 0,"invalid order status");
      require(order.startTime+7200 < block.timestamp, "not finished yet"); //total 45 mins first half, 15 mins break, 45 mins second half, 15 mins of extra time 
      order.status = 1;
      if(winner){
          order.winner = TAKER_WIN;
         
      }else{
          order.winner = MAKER_WIN;
      }
    }
    
    emit MatchSettled(groupId);
    return length>0?true:false;
  }

  /// @notice cancelling the match due to unexpected event
  /// @param groupId identifier of the group
  function cancelByOrderGroup(bytes32 groupId) public{

    uint256 length = orderGroups[groupId].length;

    for(uint256 i = 0 ; i < length ; i ++){
      Order storage order = orders[orderGroups[groupId][i]];
       require(order.startTime>0,"Invalid Match");
      uint256 currTime = block.timestamp-(24*3600); //24 hours waiting time. will be written in FAQ

      require(order.status == 0 ,"Invalid Match");
      require((msg.sender == order.takerSide) || (msg.sender == order.makerSide) || (msg.sender == refereeAddress),"You're not allowed to do this");

      if(msg.sender == refereeAddress){
        require(block.timestamp > order.startTime+14400,"Cancel Failed. Invalid Time (Ref)");
      }else{
          require(currTime > order.startTime+7200,"Cancel Failed. Invalid Time");
      }
       order.status = BOTH_WIN;
       order.winner = BOTH_WIN;
    }

   
  }

  /// @notice cancelling the match due to unexpected event
  /// @param _orderId identifier of the order / betslip
  function cancel(uint256 _orderId) public{

    require(orders[_orderId].startTime>0,"Invalid Match");
    uint256 currTime = block.timestamp-(24*3600); //24 hours waiting time. will be written in FAQ
    Order storage _order = orders[_orderId];

    require(_order.status == 0 ,"Invalid Match");
    require((msg.sender == _order.takerSide) || (msg.sender == _order.makerSide) || (msg.sender == refereeAddress),"You're not allowed to do this");

    if(msg.sender == refereeAddress){
      require(block.timestamp > _order.startTime+14400,"Cancel Failed. Invalid Time (Ref)");
    }else{
          require(currTime > _order.startTime+7200,"Cancel Failed. Invalid Time");
    }
     _order.status = BOTH_WIN;
     _order.winner = BOTH_WIN;
  }

  function addToken(address token,uint256 code) public onlyOwner{
    require(token != address(0x0),"Cannot zero address");
    allowedTokens[code]._address = token;
    allowedTokens[code].trc20 = ITRC20(token);
  }

  function removeToken(uint256 code)public onlyOwner{
    allowedTokens[code]._address = address(0);
  }
  function setMinimumBet(uint64 _MINIMUM_BET) public onlyOwner {
      MINIMUM_BET = _MINIMUM_BET;
  }

  function setReferee(address _refereeAddress) public onlyOwner{
    require(_refereeAddress != address(0x0),"Cannot zero address");
    refereeAddress = _refereeAddress;
  }

   function setProviderAddress(address _providerAddress) public onlyOwner{
    require(_providerAddress != address(0x0),"Cannot zero address");
    providerAddress = _providerAddress;
  }

}