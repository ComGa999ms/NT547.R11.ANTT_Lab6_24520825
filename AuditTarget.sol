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
        // Giu nguyen cau truc goc cua ham, chi thay tx.origin bang msg.sender:
        // msg.sender la nguoi goi truc tiep, khong bi hop dong trung gian muon danh.
        require(msg.sender == owner, "not owner");
        require(newOwner != address(0), "zero");
        owner = newOwner;
    }

    function noFunds() external view returns (bool) {
        // Chi la ham view chan doan so du; ETH co the bi ep vao contract bang
        // selfdestruct/block reward nen so sanh tuyet doi khong phai quyet dinh bao mat.
        // slither-disable-next-line incorrect-equality
        return address(this).balance == 0;
    }

    function setRewardToken(address t) external onlyOwner {
        require(t != address(0), "zero");
        stableCoin = IERC20Like(t);
    }

    function claimTokens(uint256 amount) external {
        require(amount > 0, "zero amount");
        require(points[msg.sender] >= amount, "not enough");
        points[msg.sender] -= amount;
        require(stableCoin.transfer(msg.sender, amount), "transfer failed");
    }

    function vestStep() external onlyOwner {
        // Timelock 1 ngay: sai lech ~12s cua block.timestamp khong anh huong lich
        // giai ngan, va ham da bi gioi han boi onlyOwner.
        // slither-disable-next-line timestamp
        require(block.timestamp >= cooldownEnd, "locked");
        cooldownEnd = block.timestamp + 1 days;
        (bool ok, ) = payable(owner).call{value: address(this).balance / 10}("");
        require(ok, "release failed");
    }

    function sunset() external onlyOwner {
        selfdestruct(payable(owner));
    }

    function grant(address payable to, uint256 amount) external onlyOwner {
        require(to != address(0), "zero");
        require(amount <= address(this).balance, "insufficient balance");
        (bool ok, ) = to.call{value: amount}("");
        require(ok, "send failed");
    }
}
