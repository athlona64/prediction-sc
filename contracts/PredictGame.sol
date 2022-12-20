pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBase.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract PreditctGame is VRFConsumerBase, Ownable {

    using SafeMath for uint;
   enum Status {
        Hi,
        Lo
    }   
    struct Game {
        address host;
        bool executed;
        uint256 amount;
        uint256 maxPlayers;
        uint256 currentPlayers;
        uint start;
        uint deadline;
        uint256 round;
        uint256 oracleNum;
        bytes32 requestId;
        mapping(address => Status) predict;
        mapping(address => bool) join;
        mapping(uint256 => address) players;
        bool hostOut;

    }
    // The amount of LINK to send with the request
    uint256 public feeLink;
    // ID of public key against which randomness is generated
    bytes32 public keyHash;
    uint256 public numGames;
    uint256 public fees = 0.001 ether;
    address public feesAddress;
    mapping(uint256 => Game) public gameRound;
    mapping(bytes32 => uint256) public findGame;

/**
   * constructor inherits a VRFConsumerBase and initiates the values for keyHash, fee and gameStarted
   * @param vrfCoordinator address of VRFCoordinator contract
   * @param linkToken address of LINK token contract
   * @param vrfFee the amount of LINK to send with the request
   * @param vrfKeyHash ID of public key against which randomness is generated
   */
    constructor(address vrfCoordinator, address linkToken, bytes32 vrfKeyHash, uint256 vrfFee)
    VRFConsumerBase(vrfCoordinator, linkToken) {
        keyHash = vrfKeyHash;
        feeLink = vrfFee;
        feesAddress = msg.sender;
    }
 
    event CreateGame(uint256 round, address host, uint256 maxPlayers, uint256 deadline, uint256 amount);
    event JoinGame(uint256 round, address player);
    event GameEnded(uint256 round, uint256 winners, uint256 maxPlayers);
    event WithdrawDeadline(uint256 round, address sender);

    function changeFees(uint256 _fee) external onlyOwner returns (uint256) {
        fees = _fee;
        return fees;
    }
    function changeFeetor(address _feesAddress) external onlyOwner returns (bool) {
        feesAddress = _feesAddress;
        return true;
    }
    function createGame(uint256 maxPlayers, uint256 amount) external payable returns (uint256) {
        require(msg.value == (amount.mul(maxPlayers).add(fees)), 'NOT ENOUGH');
        require(maxPlayers <= 10, "MAX IS 10");
        Game storage gameInfo = gameRound[numGames];
        numGames = numGames.add(1);
        gameInfo.host = msg.sender;
        gameInfo.amount = amount;
        gameInfo.maxPlayers = maxPlayers;
        gameInfo.start = block.timestamp;
        gameInfo.round = numGames.sub(1);
        gameInfo.deadline = block.timestamp + 4 hours; 
        //fees
            (bool sent,) = feesAddress.call{value: fees}("");
            require(sent, "Failed to send Ether");         
        emit CreateGame(numGames.sub(1), msg.sender, maxPlayers, gameInfo.deadline, amount);

        return numGames.sub(0);
    }

    function joinGame(uint256 _numGame, uint256 _predict) external payable returns (uint256) {
        require(_predict <= 1);
        Game storage gameInfo = gameRound[_numGame];
        require(msg.value == gameInfo.amount, "NOT ENOUGH");
        require(gameInfo.executed == false, "END GAME");
        require(gameInfo.deadline >= block.timestamp, "THE END");
        gameInfo.join[msg.sender] = true;
        if(_predict == 0) {
            gameInfo.predict[msg.sender] = Status.Lo;
        } else {
            gameInfo.predict[msg.sender] = Status.Hi;
        }
        
        gameInfo.currentPlayers = gameInfo.currentPlayers.add(1);
        gameInfo.players[gameInfo.currentPlayers.sub(1)] = msg.sender;
     
            if(gameInfo.currentPlayers == gameInfo.maxPlayers) {
                getRoll(_numGame);
            }

        emit JoinGame(_numGame, msg.sender);
        return _numGame;
    }

    function getRoll(uint256 _numGame) private returns (bytes32 requestId) {
        // LINK is an internal interface for Link token found within the VRFConsumerBase
        // Here we use the balanceOF method from that interface to make sure that our
        // contract has enough link so that we can request the VRFCoordinator for randomness
        require(LINK.balanceOf(address(this)) >= feeLink, "Not enough LINK");
        // Make a request to the VRF coordinator.
        // requestRandomness is a function within the VRFConsumerBase
        // it starts the process of randomness generation
        bytes32 requestIdByChainlink = requestRandomness(keyHash, feeLink);
        Game storage gameInfo = gameRound[_numGame];
        gameInfo.requestId = requestIdByChainlink;
        findGame[requestIdByChainlink] = _numGame;
        return requestIdByChainlink;
    }    

    function fulfillRandomness(bytes32 requestId, uint256 randomness) internal virtual override  {

        Game storage gameInfo = gameRound[findGame[requestId]];
            gameInfo.oracleNum = randomness % 18;
            gameInfo.executed = true;
            Status numWin;
            uint256 countWinner;
            if(gameInfo.oracleNum > 9) {
                numWin = Status.Hi;
            } else {
                numWin = Status.Lo;
            }
            
            for(uint i=0; i < gameInfo.maxPlayers; i++) {
                if(gameInfo.predict[gameInfo.players[i]] == numWin) {
                    //win
                    countWinner++;
            
                    (bool sent,) = gameInfo.players[i].call{value: gameInfo.amount}("");
                    require(sent, "Failed to send Ether");
                } else{
                    //lose
                    (bool sent,) = gameInfo.host.call{value: gameInfo.amount.mul(2)}("");
                    require(sent, "Failed to send Ether");
                }
            }
            
            emit GameEnded(gameInfo.round, countWinner, gameInfo.maxPlayers);

    }

    function withdrawDeadline(uint256 _num) external returns(uint256) {
        Game storage gameInfo = gameRound[_num];
        require(gameInfo.deadline < block.timestamp, "NOT DEADLINE");
        require(gameInfo.join[msg.sender] == true || gameInfo.host == msg.sender, "NOT YOU");
        if(gameInfo.host == msg.sender && gameInfo.hostOut == false) {
            gameInfo.hostOut = true;
            (bool sent,) = gameInfo.host.call{value: gameInfo.amount.mul(gameInfo.maxPlayers)}("");
            require(sent, "Failed to send Ether");            
        } else {
            gameInfo.join[msg.sender] = false; 
            (bool sent,) = msg.sender.call{value: gameInfo.amount}("");
            require(sent, "Failed to send Ether");            
        }

        emit WithdrawDeadline(_num, msg.sender);
        return _num;
    }

    receive() external payable {}

    fallback() external payable {}

}