// SPDX-License-Identifier: BlueOak-1.0.0
pragma solidity 0.8.4;

import "../interfaces/ICircuitBreaker.sol";
import "../deps/zeppelin/token/ERC20/ERC20.sol";

import "../Configuration.sol";

/*
 * @title SlowMintingERC20 
 * @dev An ERC20 that time-delays minting events, causing the internal balance mapping 
 * of the contract to update only after an appropriate delay. 
 * 
 * The delay is determined using a FIFO minting queue. The queue stores the block of the initial 
 * minting event. As the block number increases, mintings are taken off the queue and paid out. 
 *
 * *Contract Invariant*
 * At any reasonable setting of values this algorithm should not result in the queue growing 
 * unboundedly. In the worst case this does occur, portions of the queue can be processed 
 * manually by calling `tryProcessMintings` directly. 
 */ 
contract SlowMintingERC20 is ERC20 {

    /// Override ERC20 vars for visibility

    mapping(address => uint256) public override _balances;
    mapping(address => mapping(address => uint256)) public override _allowances;
    uint256 public override _totalSupply;

    /// SlowMinting-specific

    Configuration public conf;

    struct Minting {
        uint256 amount;
        address account;
    }

    Minting[] private mintings;
    uint256 private currentMinting;
    uint256 private lastBlockChecked;

    event MintingInitiated(address account, uint256 amount);
    event MintingComplete(address account, uint256 amount);

    constructor(
        string memory name_, 
        string memory symbol_, 
        address conf_
    ) ERC20(name_, symbol_) {
        conf = Configuration(conf_);
        lastBlockChecked = block.number;
    }


    modifier update() {
        tryProcessMintings(mintings.length - currentMinting);
        _;
    }


    /// Tries to process `count` mintings. Called before most actions.
    /// Can also be called directly if we get to the block gas limit. 
    function tryProcessMintings(uint256 count) public {
        if (!ICircuitBreaker(conf.circuitBreakerAddress()).check()) {
            uint256 blocksSince = block.number - lastBlockChecked;
            while (currentMinting < mintings.length && i < currentMinting + count) {
                Minting storage m = mintings[currentMinting];

                // Break if the next minting is too big.
                if (m.amount > conf.issuanceBlockLimit() * (blocksSince)) {
                    break;
                }
                _mint(m.account, m.amount);
                emit MintingComplete(m.account, m.amount);

                uint256 blocksUsed = m.amount / conf.issuanceBlockLimit();
                if (blocksUsed * conf.issuanceBlockLimit() > m.amount) {
                    blocksUsed = blocksUsed + 1;
                }
                blocksSince = blocksSince - blocksUsed;
                delete mintings[currentMinting]; // gas saving
                currentMinting++;
            }
        }
        lastBlockChecked = block.number;
    }

    /**
     * @dev See {IERC20-totalSupply}.
     */
    function totalSupply() public view override update returns (uint256) {
        return _totalSupply;
    }

    /**
     * @dev See {IERC20-balanceOf}.
     */
    function balanceOf(address account) public view override update returns (uint256) {
        return _balances[account];
    }

    /**
     * @dev See {IERC20-transfer}.
     *
     * Requirements:
     *
     * - `recipient` cannot be the zero address.
     * - the caller must have a balance of at least `amount`.
     */
    function transfer(address recipient, uint256 amount) public override update returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    /**
     * @dev See {IERC20-transferFrom}.
     *
     * Emits an {Approval} event indicating the updated allowance. This is not
     * required by the EIP. See the note at the beginning of {ERC20}.
     *
     * Requirements:
     *
     * - `sender` and `recipient` cannot be the zero address.
     * - `sender` must have a balance of at least `amount`.
     * - the caller must have allowance for ``sender``'s tokens of at least
     * `amount`.
     */
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public override update returns (bool) {
        _transfer(sender, recipient, amount);

        uint256 currentAllowance = _allowances[sender][_msgSender()];
        require(currentAllowance >= amount, "ERC20: transfer amount exceeds allowance");
        unchecked {
            _approve(sender, _msgSender(), currentAllowance - amount);
        }

        return true;
    }

    /** @dev Creates `amount` tokens and assigns them to `account`, increasing
     * the total supply, but only after a delay.
     *
     * Emits a {MintingInitiated} event with `from` set to the zero address.
     *
     * Requirements:
     *
     * - `account` cannot be the zero address.
     * 
     * Instead of immediately crediting balances, balances increase in 
     * the future based on conf.issuanceBlockLimit().
     */
    function mint(address account, uint256 amount) external override {
        require(_msgSender() == address(this), "ERC20: mint is only callable by self");
        require(account != address(0), "ERC20: mint to the zero address");

        Minting memory m = Minting(amount, account);
        mintings.push(m);
        emit MintingInitiated(account, amount);
    }
}