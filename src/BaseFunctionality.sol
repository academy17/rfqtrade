// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;
//ABSTRACT CONTRACTS ACT LIKE WRAPPER, SETTER/GETTERS GO IN HERE
import "./AppStorage.sol";

abstract contract BaseFunctionality is AppStorage {
//GETTERS
    function getBCloseQuoteContractIds(uint256 bCloseQuoteId) public view returns(uint256[] memory) {
        bCloseQuote memory _bCloseQuote = bCloseQuotes[bCloseQuoteId];
        return _bCloseQuote.bContractIds;
    }

    function getBCloseQuotePrices(uint256 bCloseQuoteId) public view returns(uint256[] memory) {
        bCloseQuote memory _bCloseQuote = bCloseQuotes[bCloseQuoteId];
        return _bCloseQuote.price;
    }

    function getOpenPositionNumber(address user) public view returns (uint256) {
        return openPositionNumber[user];
    }

    function getBContractMemory(uint256 id) public view returns (bContract memory) {
            return bContracts[id];
    }

    function getBalance(address account) public view returns (uint256) {
            return balances[account];
    }

    function getBOracleLength() public view returns (uint256) {
        return bOracleLength;
    }
    
    function getBOracle(uint256 id) public view returns (bOracle memory) {
        return bOracles[id];
    }

    function getBContractLength() public view returns (uint256) {
        return bContractLength;
    }

    function getBContract(uint256 id) public view returns (bContract memory) {
        return bContracts[id];
    }

    function getBCloseQuotesLength() public view returns (uint256) {
        return bCloseQuotesLength;
    }

    function getBCloseQuote(uint256 id) public view returns (bCloseQuote memory) {
        return bCloseQuotes[id];
    }

    function getOwedAmount(address owner, address spender) public view returns (uint256) {
        return owedAmounts[owner][spender];
    }

    function getTotalOwedAmount(address addr) public view returns (uint256) {
        return totalOwedAmounts[addr];
    }

    function getTotalOwedAmountPaid(address addr) public view returns (uint256) {
        return totalOwedAmountPaids[addr];
    }

    function getGracePeriodLockedWithdrawBalance(address addr) public view returns (uint256) {
        return gracePeriodLockedWithdrawBalances[addr];
    }

    function getGracePeriodLockedTime(address addr) public view returns (uint256) {
        return gracePeriodLockedTime[addr];
    }

    function getMinimumOpenPartialFillNotional(address addr) public view returns (uint256) {
        return minimumOpenPartialFillNotional[addr];
    }

    function getSponsorReward(address addr) public view returns (uint256) {
        return sponsorReward[addr];
    }

//INCREMENT/DECREMENT
    function incrementbCloseQuotes() internal {
        bCloseQuotesLength++;
    }

    function incrementbContractLength() internal  {
        bContractLength++;
    }

    function incrementOpenPositionNumber(address user) internal  {
        openPositionNumber[user]++;
    }

    function decrementOpenPositionNumber(address user) internal  {
        openPositionNumber[user]--;
    }

//SETTER FUNCTIONS
    function setBalance(address _party, uint256 _amount) internal {
        balances[_party] = _amount;
    }

    function setBContractParty(address _party, uint256 bContractID, bool isPartyA) internal {
            bContract storage newContract = bContracts[bContractID];
            if(isPartyA) {
                newContract.partyA = _party;
            } else {
                newContract.partyB = _party;
            }
    }

    function setBContractQuantity(uint256 bContractId, uint256 _qty) internal {
        bContract storage newContract = bContracts[bContractId];
        newContract.qty = _qty;
    }   


    function setBCloseQuoteQtyZero(uint256 bCloseQuoteId, uint256 index) internal { //@audit
            bCloseQuote storage _bCloseQuote = bCloseQuotes[bCloseQuoteId];
            _bCloseQuote.qty[index] = 0;

    }

    function setBCloseQuoteState(uint256 bCloseQuoteId, _State state) internal { //@audit
            bCloseQuote storage _bCloseQuote = bCloseQuotes[bCloseQuoteId];
            _bCloseQuote.state = state;

    }
    

    function setBContractAffiliate(uint256 bContractId, address _backEndAffiliate) internal {
        bContract storage newContract = bContracts[bContractId];
        newContract.backEndAffiliate = _backEndAffiliate;
    }

    function setBContractState(uint256 bContractId, _State newState) internal {
            bContract storage newContract = bContracts[bContractId];
            newContract.state = newState;
    }

    function setBContractPrice(uint256 bContractID, uint256 _price) internal {
            bContract storage newContract = bContracts[bContractID];
            newContract.price = _price;
    }

    function setBContractOpenTime(uint256 _bContractId, uint256 _openTime) internal {
        bContract storage newContract = bContracts[_bContractId];
        newContract.openTime = _openTime;
    }

    function setBContractStateMemory(bContract storage _bContract, _State newState) internal {
        
        _bContract.state = newState;
    }

    function setBContractCancelTimeMemory(bContract storage _bContract, uint256 _time) internal{
        _bContract.cancelTime = _time;
    }

    function setBContractPriceMemory(bContract storage _bContract, uint256 _price) internal {
        _bContract.price = _price;

    }

    function setbContractVariablesQuote(
        address initiator,
        uint256 bContractID,
        uint256 bOracleId,
        uint256 price,
        uint256 qty,
        uint256 interestRate, 
        bool isAPayingAPR, 
        address frontEndAffiliate, 
        address frontEndAffiliateAffiliate
    ) internal {
            bContract storage newContract = bContracts[bContractID];
            newContract.initiator = initiator;
            newContract.price = price;
            newContract.qty = qty;
            newContract.interestRate = interestRate;
            newContract.isAPayingAPR = isAPayingAPR;
            newContract.oracleId = bOracleId;
            newContract.state = _State.Quote;
            newContract.frontEndAffiliate = frontEndAffiliate;
            newContract.frontEndAffiliateAffiliate = frontEndAffiliateAffiliate;
            newContract.openTime = block.timestamp;
    }

    function setBContractCloseQuote(
        uint256[] memory _bContractIds,
        uint256[] memory _price, 
        uint256[] memory _qty, 
        uint256[] memory _limitOrStop, 
        address _initiator,
        uint256 _expiration
    ) public {
        bCloseQuote storage newQuote = bCloseQuotes[bCloseQuotesLength];
        newQuote.bContractIds = _bContractIds;
        newQuote.price = _price;
        newQuote.qty = _qty;
        newQuote.limitOrStop = _limitOrStop;
        newQuote.initiator = _initiator;
        newQuote.expiration = _expiration;
        newQuote.cancelTime = 0;
        newQuote.openTime = block.timestamp;
        newQuote.state = _State.Quote;
        emit openCloseQuoteEvent(msg.sender, bCloseQuotesLength, _bContractIds, _price, _qty, _limitOrStop, _expiration);
        incrementbCloseQuotes();
    }


/*
    function getBCloseQuoteContractIds(uint256 bCloseQuoteId) internal view virtual returns(uint256[] memory); 
    function getBCloseQuotePrices(uint256 bCloseQuoteId) internal view virtual returns(uint256[] memory); 
    function getOpenPositionNumber(address user) internal view virtual returns (uint256); 
    function getBContractMemory(uint256 id) internal view virtual returns (bContract memory); 
    function getBalance(address account) internal view virtual returns (uint256); 
    function getBOracleLength() public view virtual returns (uint256);
    function getBOracle(uint256 id) public view virtual returns (bOracle memory);
    function getBContractLength() public view virtual returns (uint256); 
    function getBContract(uint256 id) public view virtual returns (bContract memory); 
    function getBCloseQuotesLength() public view virtual returns (uint256); 
    function getBCloseQuote(uint256 id) public view virtual returns (bCloseQuote memory); 
    function getOwedAmount(address owner, address spender) public view virtual returns (uint256); 
    function getTotalOwedAmount(address addr) public view virtual returns (uint256); 
    function getTotalOwedAmountPaid(address addr) public view virtual returns (uint256); 
    function getGracePeriodLockedWithdrawBalance(address addr) public view virtual returns (uint256); 
    function getGracePeriodLockedTime(address addr) public view virtual returns (uint256); 
    function getMinimumOpenPartialFillNotional(address addr) public view virtual returns (uint256); 
    function getSponsorReward(address addr) public view virtual returns (uint256); 
*/

    }
