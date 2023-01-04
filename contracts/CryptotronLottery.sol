/* Copyright 2022 Andrey Novikov

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License. */

// SPDX-License-Identifier: Apache-2.0

/*_________________________________________CRYPTOTRON_________________________________________*/

pragma solidity ^0.8.7;

import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AutomationCompatibleInterface.sol";
import "hardhat/console.sol";

/**
* @dev interface of NFT smart contract, that provides functionality 
* @dev for enterCryptotron function.
*/
interface CryptoTicketInterface {
    /**
    * @dev returns the owner address of a specific token
    */
    function ownerOf(uint256 tokenId) external view returns (address);

    /**
    * returns the ammount of supported tokens within current contract
    */
    function sold() external view returns (uint256 ammount);
}

interface IERC20 {
    /**
    * @dev Returns the amount of tokens in existence.
    */
    function totalSupply() external view returns (uint256);

    /**
    * @dev Returns the amount of tokens owned by `account`.
    */
    function balanceOf(address account) external view returns (uint256);

    /**
    * @dev Moves `amount` tokens from the caller's account to `recipient`.
    *
    * Returns a boolean value indicating whether the operation succeeded.
    *
    * Emits a {Transfer} event.
    */
    function transfer(address recipient, uint256 amount) external returns (bool);

    /**
    * @dev Returns the remaining number of tokens that `spender` will be
    * allowed to spend on behalf of `owner` through {transferFrom}. This is
    * zero by default.
    *
    * This value changes when {approve} or {transferFrom} are called.
    */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
    * @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
    *
    * Returns a boolean value indicating whether the operation succeeded.
    *
    * IMPORTANT: Beware that changing an allowance with this method brings the risk
    * that someone may use both the old and the new allowance by unfortunate
    * transaction ordering. One possible solution to mitigate this race
    * condition is to first reduce the spender's allowance to 0 and set the
    * desired value afterwards:
    * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
    *
    * Emits an {Approval} event.
    */
    function approve(address spender, uint256 amount) external returns (bool);

    /**
    * @dev Moves `amount` tokens from `sender` to `recipient` using the
    * allowance mechanism. `amount` is then deducted from the caller's
    * allowance.
    *
    * Returns a boolean value indicating whether the operation succeeded.
    *
    * Emits a {Transfer} event.
    */
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);

    /**
    * @dev Emitted when `value` tokens are moved from one account (`from`) to
    * another (`to`).
    *
    * Note that `value` may be zero.
    */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
    * @dev Emitted when the allowance of a `spender` for an `owner` is set by
    * a call to {approve}. `value` is the new allowance.
    */
    event Approval(address indexed owner, address indexed spender, uint256 value);
}


/**
* @dev Errors.
*/

error UE(uint256 currentBalance, uint256 numPlayers, uint256 cryptotronState);
error TE();
error SE();
error FE();
error DE();
error OE();
error ZE();
error RE();


/**@title CryptoGamble project
* @author Andrey Novikov
*/
contract CryptotronLottery is VRFConsumerBaseV2, AutomationCompatibleInterface {

    /**
   * @dev Cryptotron state diclaration.
   */
    enum cryptotronState {
        OPEN,
        CALCULATING
    }

    /**
   * @dev Variables.
   */
    VRFCoordinatorV2Interface private immutable i_vrfCoordinator;
    cryptotronState private s_cryptotronState;
    bytes32 private immutable i_gasLane;
    uint256 private immutable i_interval;
    uint256 private s_lastTimeStamp;
    uint256 private refundAmmount;
    uint256 private indexOfWinner;
    uint256 private tokenId;
    uint64 private immutable i_subscriptionId;
    uint32 private immutable i_callbackGasLimit;
    uint32 private constant NUM_WORDS = 1;
    uint16 private constant REQUEST_CONFIRMATIONS = 4;
    address payable[] private s_players;
    address[] private s_allWinners;
    address[] internal deprecatedContracts;
    address private ticketAddress;
    address private tokenAddress;
    address private s_recentWinner;
    address payable public owner;
    address private nullAddress = address(0x0);
    bool private failure = false;

    /**
   * @dev Events for the future dev.
   */
    event RequestedCryptotronWinner(uint256 indexed requestId);
    event CryptotronEnter(address indexed player);
    event WinnerPicked(address indexed winner);
    event TicketAddressChanged(address indexed newAddress);
    event TokenAddressChanged(address indexed newAddress);
    event EmergencyRefund(address indexed refunder);
    event FailureWasReset(uint256 indexed timesReset);
    event CurrencyLanded(address indexed funder);
    event TokensLanded(address indexed funder, uint256 indexed ammount);
    event TokensTransfered(address indexed recipient);

    /**
   * @dev Replacement for the reqire(msg.sender == owner);
   */
    modifier onlyOwner() {
        if (msg.sender != owner) {
            revert();
        }
        _;
    }

    /**
   * @dev Replacement for the reqire(ticketAddress == nullAddress);
   */
    modifier ticketContractRestriction() {
        if (ticketAddress != nullAddress) {
            revert();
        }
        _;
    }

    /**
   * @dev Replacement for the reqire(tokenAddress == nullAddress);
   */
    modifier tokenContractRestriction() {
        if (tokenAddress != nullAddress) {
            revert();
        }
        _;
    }

    /**
   * @dev Replacement for the reqire(failure == false);
   */
    modifier checkFailure() {
        if (failure != false) {
            revert();
        }
        _;
    }

    /**
   * @dev Replacement for the reqire(failure == true);
   */
    modifier approveFailure() {
        if (failure != true) {
            revert();
        }
        _;
    }

    mapping(uint256 => string) private _tokenURIs;

    /**
   * @dev Constructor with the arguments for the VRFConsumerBaseV2
   */
    constructor(
        bytes32 gasLane,
        uint256 interval,
        uint64 subscriptionId,
        uint32 callbackGasLimit,
        address vrfCoordinatorV2
    ) VRFConsumerBaseV2(vrfCoordinatorV2) {
        i_vrfCoordinator = VRFCoordinatorV2Interface(vrfCoordinatorV2);
        i_gasLane = gasLane;
        i_interval = interval;
        i_subscriptionId = subscriptionId;
        i_callbackGasLimit = callbackGasLimit;
        s_cryptotronState = cryptotronState.OPEN;
        s_lastTimeStamp = block.timestamp;
        owner = payable(msg.sender);
        ticketAddress = tokenAddress = nullAddress;
    }

    /**
   * @notice Method that is actually executed by the keepers, via the registry.
   * @notice The data returned by the checkUpkeep simulation will be passed into
   * @notice this method to actually be executed.
   * 
   * @dev calldata (aka performData) is the data which was passed back from the checkData
   * @dev simulation. If it is encoded, it can easily be decoded into other types by
   * @dev calling `abi.decode`. This data should not be trusted, and should be
   * @dev validated against the contract's current state.
   * 
   * @notice requestRandomWords (request a set of random words).
   * @dev gasLane (aka keyHash) - Corresponds to a particular oracle job which uses
   * that key for generating the VRF proof. Different keyHash's have different gas price
   * ceilings, so you can select a specific one to bound your maximum per request cost.
   * @dev i_subscriptionId  - The ID of the VRF subscription. Must be funded
   * with the minimum subscription balance required for the selected keyHash.
   * @dev REQUEST_CONFIRMATIONS - How many blocks you'd like the
   * oracle to wait before responding to the request. See SECURITY CONSIDERATIONS
   * for why you may want to request more. The acceptable range is
   * [minimumRequestBlockConfirmations, 200].
   * @dev i_callbackGasLimit - How much gas you'd like to receive in your
   * fulfillRandomWords callback. Note that gasleft() inside fulfillRandomWords
   * may be slightly less than this amount because of gas used calling the function
   * (argument decoding etc.), so you may need to request slightly more than you expect
   * to have inside fulfillRandomWords. The acceptable range is
   * [0, maxGasLimit]
   * @dev NUM_WORDS - The number of uint256 random values you'd like to receive
   * in your fulfillRandomWords callback. Note these numbers are expanded in a
   * secure way by the VRFCoordinator from a single random value supplied by the oracle.
   * @dev requestId - A unique identifier of the request. Can be used to match
   * a request to a response in fulfillRandomWords.
   */
    function performUpkeep(
        bytes calldata
    ) external override checkFailure {
        enterCryptotron();
        IERC20 token = IERC20(tokenAddress);
        (bool upkeepNeeded, ) = checkUpkeep("");
        if (!upkeepNeeded) {
            failure = true;
            revert UE(
                token.balanceOf(address(this)),
                s_players.length,
                uint256(s_cryptotronState)
            );
        }
        s_cryptotronState = cryptotronState.CALCULATING;
        uint256 requestId = i_vrfCoordinator.requestRandomWords(
            i_gasLane,
            i_subscriptionId,
            REQUEST_CONFIRMATIONS,
            i_callbackGasLimit,
            NUM_WORDS
        );
        emit RequestedCryptotronWinner(requestId);
    }

    /**
   * @dev Checker function. When Chainlink Automation calls performUpkeep
   * @dev function it calls this checker function and waits for it to return
   * @dev boolean true so performUpkeep can proceed and make request to ChainlinkVRF. 
   * @dev Params checked: current state, passed time, players ammount, balance of the contract.
   */
    function checkUpkeep(
        bytes memory
    ) public view override returns (bool upkeepNeeded, bytes memory) {
        IERC20 token = IERC20(tokenAddress);
        bool isOpen = cryptotronState.OPEN == s_cryptotronState;
        bool timePassed = ((block.timestamp - s_lastTimeStamp) > /*7 days, dev = */ i_interval);
        bool hasPlayers = s_players.length > 0;
        bool hasBalance = token.balanceOf(address(this)) > 0;
        bool maintained = address(this).balance > 0;
        upkeepNeeded = (timePassed && isOpen && hasBalance && maintained && hasPlayers);
        return (upkeepNeeded, "0x0");
    }

    /**
   * @dev This function is for changing the contract of Cryptotron Tickets
   * @dev that becomes reachable only after recent address becomes nullAddress
   * @dev (which means that the last draw is over). Also it's failure restrickted
   * @dev (bool failure == false) and can be called only by owner.
   */
    function changeTicketAddress(address newAddress) public onlyOwner checkFailure ticketContractRestriction {
        ticketAddress = newAddress;
        emit TicketAddressChanged(newAddress);
    }

    /**
   * @dev This function is for changing the contract of Cryptotron Token
   * @dev that becomes reachable only after recent address becomes nullAddress
   * @dev (which means that the last draw is over). Also it's failure restrickted
   * @dev (bool failure == false) and can be called only by owner.
   */
    function changeTokenAddress(address newAddress) public onlyOwner checkFailure tokenContractRestriction {
        tokenAddress = newAddress;
        emit TokenAddressChanged(newAddress);
    }

    // function changeWinningURI(string memory newURI) public onlyOwner {
    //     _tokenURI = newURI;
    // }

    /**
   * @dev This fuction is for refunding purchased tickets to Cryptotron
   * @dev members during an emergency (bool failure = true).
   * @dev Function is public, so everyone can call it.
   * @dev Keeps track of callers of this function.
   */
    function emergencyRefund() public approveFailure {
        ticketAddress = nullAddress;
        IERC20 token = IERC20(tokenAddress);
        if (token.balanceOf(address(this)) == 0) {
            revert RE();
        } else {
            refundAmmount = (token.balanceOf(address(this)) / s_players.length);
            for (uint i = 0; i < s_players.length; i++) {
                s_players[i].transfer(refundAmmount);
            }
        }
        emit EmergencyRefund(msg.sender);
    }

    /**
   * @dev This function will be used to reset falure state of the Cryptotron
   * @dev only after required tests of failed version.
   *  
   * @notice Maybe this function will never be touched.
   */
    function resetFailure(uint256 timesReset) public onlyOwner {
        timesReset += timesReset;
        failure = false;
        emit FailureWasReset(timesReset);
    }

    /**
   * @dev This function was made just for funding the Cryptotron for providing
   * @dev transactions (service) on current network with it's native currency.
   *
   * @notice Do not use this function to enter the Cryptotron.
   */
    function fundCryptotronService() public payable checkFailure {
        emit CurrencyLanded(msg.sender);
    }

    /**
   * @dev This function was made just for funding the Cryptotron.
   *
   * @notice You can increase lottery winnings. But it is not changing
   * @notice youre chances for the win. We are storing your address for future. :)
   *
   * @notice Do not use this function to enter the Cryptotron.
   */
    function fundCryptotronToken(uint256 _ammount) public checkFailure {
        IERC20 token = IERC20(tokenAddress);
        require(_ammount > 0, "");
        token.transferFrom(msg.sender, address(this), _ammount);
        emit TokensLanded(msg.sender, _ammount);
    }

    /**
   * @dev VRFConsumerBaseV2 expects its subcontracts to have a method with this
   * @dev signature, and will call it once it has verified the proof
   * @dev associated with the randomness. (It is triggered via a call to
   * @dev rawFulfillRandomness, below.)
   * @dev After receiving a random word (aka random number), this function will
   * @dev choose the winner and "call" him the entire balance of this contract.
   * 
   * @dev (uint256 aka requestId) the Id initially returned by requestRandomness.
   * @param randomWords the VRF output expanded to the requested number of words
   */
    function fulfillRandomWords(
        uint256, 
        uint256[] memory randomWords
    ) internal override checkFailure {
        IERC20 token = IERC20(tokenAddress);
        indexOfWinner = randomWords[0] % s_players.length;
        uint256 _tokenId = indexOfWinner;
        address payable recentWinner = s_players[indexOfWinner];
        s_recentWinner = recentWinner;
        s_allWinners.push(recentWinner);
        deprecatedContracts.push(ticketAddress);
        ticketAddress = nullAddress;
        address recipient = recentWinner;
        uint256 amount = token.balanceOf(address(this));
        uint256 trophy = (amount * 8 / 10);
        (bool success) = token.transfer(recipient, trophy);
        if (!success) {
            failure = true;
            revert TE();
        }
        // _setTokenURI(_tokenId, _tokenURI);
        tokenAddress = nullAddress;
        s_players = new address payable[](0);
        s_lastTimeStamp = block.timestamp;
        s_cryptotronState = cryptotronState.OPEN;
        emit WinnerPicked(recentWinner);
    }

    // function _setTokenURI(uint256, string memory) internal override (CryptotronTicket) {
    //     _tokenURIs[tokenId] = _tokenURI;
    // }


    /**
   * @dev enterCryptotron is the internal function that is getting kicked off
   * @dev by performUpkeep and sets the cryptotron players aka owners of each
   * @dev ticket (owner of each tokenId).
   * 
   * @notice Number of players determaned by the quantity of
   * @notice tokenIds which were minted with the actual NFT contract (you allways
   * @notice can check the ammount of tickets, prices ect. by calling ticketAddress
   * @notice function on Etherscan. Path: Etherscan -> address (this) ->
   * @notice -> Contract -> Read Contract -> ticketAddress -> Nft contract ->
   * @notice -> Read Contract)
   */
    function enterCryptotron() internal checkFailure {
        if (s_cryptotronState != cryptotronState.OPEN) {
            revert();
        }
        CryptoTicketInterface cti = CryptoTicketInterface(ticketAddress);
        for (tokenId = 0; tokenId < cti.sold(); tokenId++) {
            s_players.push(payable(cti.ownerOf(tokenId)));
            emit CryptotronEnter(cti.ownerOf(tokenId));
        }
    }   

    /**
   * @dev Returns the balance of the Cryptotron contract (service)
   * 
   * @notice This funds are the "Service currency" of the Cryptotron
   */
    function getServiceBalance() public view returns (uint256) {
        return address(this).balance;
    }

    /**
   * @dev Returns the balance of the Cryptotron contract (winnings)
   * 
   * @notice This funds are the "Jackpot" of the Cryptotron
   */
    function getWinningsBalance() public view returns (uint256) {
        IERC20 token = IERC20(tokenAddress);
        return token.balanceOf(address(this));
    }

    /**
   * @dev Returns the address of the NFT contract on which
   * @dev the tickets for the current draw were minted
   * 
   * @notice If you want to participate in the next draw
   * @notice you need to buy a ticket with the contract address
   * @notice that matches the address that this function
   * @notice returns.
   * 
   * @notice If you are getting a null address, please wait
   * @notice until we are done setting up a new address with
   * @notice new tickets.
   */
    function getTicketAddress() public view returns (address) {
        return ticketAddress;
    }

    /**
   * @dev Returns the address of the ERC20 token which
   * @dev is the current draw currency.
   * 
   * @notice If you are getting a null address, please wait
   * @notice until we are done setting up a new address with
   * @notice new tickets and tokens (tokens address in the normal
   * @notice situation will not be changed from WETH address).
    */
    function getTokenAddress() public view returns (address) {
        return tokenAddress;
    }

    /**
   * @dev Returns an array of previous draws.
   */
    function getDeprecatedContracts() public view returns (address[] memory) {
        return deprecatedContracts;
    }

    /**
   * @dev Returns enum type value (0 - Cryptotron is open, 1 - Cryptotron is calculating).
   */
    function getCryptotronState() public view returns (cryptotronState) {
        return s_cryptotronState;
    }

    /**
   * @dev Returns previous winner.
   */
    function getRecentWinner() public view returns (address) {
        return s_recentWinner;
    }

    /**
   * @dev Returns the value in seconds when the recent draw was played.
   */
    function getLastTimeStamp() public view returns (uint256) {
        return s_lastTimeStamp;
    }

    /**
   * @dev Returns an array of all previous winners.
   */
    function getAllWinners() public view returns (address[] memory) {
        return s_allWinners;
    }

    /**
   * @dev Returns true if there was a failure during the draw.
   */
    function getFailed() public view returns (bool) {
        return failure;
    }

}