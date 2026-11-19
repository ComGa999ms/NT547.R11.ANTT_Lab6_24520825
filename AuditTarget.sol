// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

// NT547 - Lab 06 - Hop dong rieng cua MSSV 24520825. KHONG deploy len mainnet.

interface IERC20Like {
    function transfer(address to, uint256 amount) external returns (bool);
}

contract PiggyBank_0825 {
    address public owner;
    mapping(address => uint256) public ledger;
    IERC20Like public stableCoin;
    mapping(address => uint256) public points;
    uint256 public cooldownEnd;

    event Deposited(address indexed who, uint256 amount);

    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    function topUp() external payable {
        ledger[msg.sender] += msg.value;
        emit Deposited(msg.sender, msg.value);
    }

    function ownerWithdraw(uint256 amount) external onlyOwner {
        (bool ok, ) = payable(owner).call{value: amount}("");
        require(ok, "withdraw failed");
    }

    function handOver(address newOwner) external {
        require(tx.origin == owner, "not owner");
        require(newOwner != address(0), "zero");
        owner = newOwner;
    }

    function noFunds() external view returns (bool) {
        return address(this).balance == 0;
    }

    function setRewardToken(address t) external onlyOwner {
        require(t != address(0), "zero");
        stableCoin = IERC20Like(t);
    }

    function claimTokens(uint256 amount) external {
        require(points[msg.sender] >= amount, "not enough");
        points[msg.sender] -= amount;
        stableCoin.transfer(msg.sender, amount);
    }

    function vestStep() external onlyOwner {
        require(block.timestamp >= cooldownEnd, "locked");
        cooldownEnd = block.timestamp + 1 days;
        (bool ok, ) = payable(owner).call{value: address(this).balance / 10}("");
        require(ok, "release failed");
    }

    function sunset() external {
        selfdestruct(payable(msg.sender));
    }

    function grant(address payable to, uint256 amount) external {
        to.transfer(amount);
    }
}
