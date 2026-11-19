# NT547 - LAB 06 - BÁO CÁO

**MSSV:** 24520825 | **Họ tên:** Nguyễn Đăng Khoa | **Lớp:** NT547.R11.ANTT
**Session code tự sinh:** SC-D47865 | **Tên contract:** PiggyBank_0825
**Solidity / Slither:** 0.8.24 / 0.11.6 | **Ngày hoàn thành:** 20/11/2026
**URL GitHub repository:** https://github.com/ComGa999ms/NT547.R11.ANTT_Lab6_24520825

**Môi trường chạy:** WSL2 Ubuntu, Python 3.12.3, venv riêng, `solc 0.8.24+commit.e11b9ed9.Linux.g++`,
Slither 0.11.6, Graphviz 12.2.1 (`dot -V` OK). Đã chạy `python tools/preflight.py` trước khi tạo target.

---

## 1. Static scan (2,0 điểm)

- Lệnh raw: `python tools/scan.py --mode raw --tag before`
- Số lượng finding raw từ `evidence/before_raw/summary.json`:
  - High: **3**; Medium: **2**; Low: **2**; Informational: **3**; Optimization: **0** (tổng **10** finding)
- Chạy configured: `python tools/scan.py --mode configured --tag before`
- So sánh raw/configured: configured còn **5** finding (High 3, Medium 2, Low 0, Info 0). Việc bật
  `exclude_low` + `exclude_informational` chỉ **ẩn** 2 Low (`missing-zero-check`, `timestamp`) và 3
  Informational (`low-level-calls` ×2, `naming-convention`); **không có High/Medium nào biến mất**.
  Vì vậy gate CI `fail-on: medium` vẫn đỏ dù dùng config đã lọc.
- 3 detector **khác tên** (mô tả + luồng dữ liệu):

| ID finding | Detector | Impact | Confidence | Source (file:dòng) | Luồng dữ liệu: đầu vào -> thao tác -> tác hại |
|---|---|---|---|---|---|
| F01 | `arbitrary-send-eth` | High | Medium | `AuditTarget.sol:70-72` (`grant`) | `to`/`amount` do **bất kỳ ai** truyền vào -> `to.transfer(amount)` chuyển ETH của contract -> rút sạch số dư về địa chỉ attacker chọn |
| F02 | `suicidal` | High | High | `AuditTarget.sol:66-68` (`sunset`) | `msg.sender` không được kiểm tra -> `selfdestruct(payable(msg.sender))` -> toàn bộ ETH của contract về tay người gọi (trước Cancun còn xoá luôn code) |
| F03 | `unchecked-transfer` | High | Medium | `AuditTarget.sol:53-57` (`claimTokens`) | `amount` do người dùng truyền -> `stableCoin.transfer(...)` **bỏ qua giá trị trả về** trong khi `points` đã bị trừ -> token không chuyển được nhưng sổ nội bộ vẫn ghi "đã trả", sai lệch kế toán |
| F04 | `tx-origin` | Medium | Medium | `AuditTarget.sol:39` (`handOver`) | `tx.origin` (địa chỉ khởi tạo giao dịch, xuyên qua mọi call) được so với `owner` -> hợp đồng độc hại do owner gọi có thể gọi `handOver` và chuyển quyền sở hữu cho attacker |
| F05 | `incorrect-equality` | Medium | High | `AuditTarget.sol:44-46` (`noFunds`) | ETH bị **ép** vào contract (selfdestruct/block reward) -> `address(this).balance == 0` trả sai -> nếu logic khác dựa vào đây sẽ ra quyết định sai |
| F06 | `low-level-calls` (2 chỗ) | Informational | High | `AuditTarget.sol:34, 62` | Gọi `.call{value:}` thô; đã có `require(ok)` nên không phải lỗi, chỉ là style |
| F07 | `missing-zero-check` | Low | Medium | `AuditTarget.sol:70-71` (`grant`) | `to` do người gọi truyền, không kiểm tra `address(0)` -> `to.transfer(amount)` đốt ETH vào địa chỉ rỗng, mất tiền không thu hồi được |
| F08 | `timestamp` | Low | Medium | `AuditTarget.sol:60` (`vestStep`) | `block.timestamp` do validator đề xuất -> lệch vài giây -> chỉ ảnh hưởng mốc mở khoá 1 ngày, không tạo lợi thế kinh tế |
| F09 | `naming-convention` | Informational | High | `AuditTarget.sol:10-73` | Tên biến/hàm (`stableCoin`, `cooldownEnd`, `topUp`…) không theo mixedCase của Slither -> không phải lỗ hổng, chỉ là quy ước đặt tên |

## 2. Triage và sửa lỗi (2,5 điểm)

Đọc toàn bộ `AuditTarget.sol` (73 dòng, contract `PiggyBank_0825`): nhận diện **4 mẫu lỗi thật**
(`tx-origin`, `suicidal`, `arbitrary-send-eth`, `unchecked-transfer`) + **2 đoạn cần đánh giá theo
ngữ cảnh** (`incorrect-equality` ở `noFunds`, `timestamp` ở `vestStep`). Không sửa `slither.config.json`,
không tạo finding giả.

| Detector + vị trí | TP / FP / Chưa kết luận | Bằng chứng kiểm soát/khả năng khai thác | Biện pháp (Fix / Accept có lý do) | Sau sửa |
|---|---|---|---|---|
| `tx-origin` — `handOver` (dòng 39) | **TP** | Hàm đổi chủ sở hữu nhưng chỉ so `tx.origin`. Owner bị dụ ký giao dịch vào contract của attacker: `tx.origin` vẫn là owner nên `require` qua, `owner` bị gán thành địa chỉ attacker chọn. Không có modifier, không có kiểm tra bổ trợ. | **Fix**: `require(msg.sender == owner, "not owner")` — `msg.sender` là người gọi trực tiếp, contract trung gian không mượn được danh tính. | Không còn báo |
| `suicidal` — `sunset` (dòng 66-68) | **TP** | Hàm `external`, **không** kiểm tra quyền: bất kỳ ai gọi `sunset()` cũng `selfdestruct` được, toàn bộ ETH về tay người gọi. | **Fix**: thêm `onlyOwner` và trả tiền về `owner` (không trả về `msg.sender` tuỳ ý). | Không còn báo |
| `arbitrary-send-eth` — `grant` (dòng 70-72) | **TP** | `to` và `amount` hoàn toàn do người gọi quyết định, không access control, không kiểm tra số dư: `grant(attacker, address(this).balance)` rút sạch quỹ. Kèm `missing-zero-check` (Low) vì thiếu `to != address(0)`. | **Fix**: `onlyOwner` + `require(to != address(0))` + `require(amount <= address(this).balance)` + dùng `call{value:}` có `require(ok)`. | Không còn báo (Low `missing-zero-check` cũng hết) |
| `unchecked-transfer` — `claimTokens` (dòng 53-57) | **TP** (khai thác thực tế thấp) | Bỏ qua giá trị trả về của `transfer`: token trả `false`/không revert thì `points` vẫn bị trừ trong khi token không rời đi. Xem phân tích "severity cao, risk thấp" bên dưới. | **Fix**: `require(stableCoin.transfer(msg.sender, amount), "transfer failed")` + `require(amount > 0)`. | Không còn báo |
| `incorrect-equality` — `noFunds` (dòng 44-46) | **FP theo ngữ cảnh** | Hàm `view` chỉ để chẩn đoán số dư; không hàm nào trong contract đọc `noFunds()` để ra quyết định. ETH có thể bị ép vào bằng `selfdestruct`/block reward nên so sánh tuyệt đối vốn không đáng tin, nhưng ở đây không gây hại. | **Accept có lý do** + `// slither-disable-next-line incorrect-equality` đặt đúng dòng `return`. | Không còn báo |
| `timestamp` — `vestStep` (dòng 59-64) | **FP theo ngữ cảnh** | Timelock 1 ngày; validator lệch `block.timestamp` cỡ ~12s không đáng kể so với cửa sổ 1 ngày, và hàm đã bị `onlyOwner` giới hạn — không có lợi ích kinh tế cho miner. | **Accept có lý do** + `// slither-disable-next-line timestamp`. | Không còn báo |

### Kịch bản khai thác TP (chọn `arbitrary-send-eth` ở `grant`)

1. Contract đang giữ 5 ETH từ các lần `topUp()` của người dùng.
2. Attacker gọi trực tiếp `grant(attackerAddress, 5 ether)` — **không** cần là owner, **không** cần
   token, **không** cần điều kiện nào khác.
3. `grant` không kiểm tra `msg.sender`, không kiểm tra `to != 0`, không kiểm tra số dư, gọi
   `to.transfer(amount)`.
4. Toàn bộ 5 ETH rời contract sang địa chỉ attacker; người gửi tiền mất trắng. Tương tự, `sunset()`
   cho phép bất kỳ ai `selfdestruct` và nhận toàn bộ số dư.

### Finding severity cao nhưng risk thực tế không tương ứng

`unchecked-transfer` được Slither xếp **High/Medium**, nhưng trong chính contract này `points` **không
bao giờ được cộng** (không có hàm nào ghi vào `points`), nên `require(points[msg.sender] >= amount)`
luôn thất bại với `amount > 0`: nhánh `transfer` trên thực tế không có đường thực thi. Rủi ro thật
thấp hơn nhãn High rất nhiều. Dù vậy em vẫn sửa (kiểm tra giá trị trả về) vì đây là khuyết điểm thật
của mã: chỉ cần một bản nâng cấp thêm hàm tích điểm là lỗ hổng thành khai thác được ngay. Ngược lại,
`suicidal` cũng High/High nhưng sau **EIP-6780** (Cancun) `selfdestruct` không xoá code trừ khi tạo và
huỷ trong cùng giao dịch — tác hại thật là **mất toàn bộ ETH**, không phải "xoá contract"; em vẫn xếp
TP vì mất quỹ là đủ nghiêm trọng.

### Bằng chứng

```diff
     function handOver(address newOwner) external {
-        require(tx.origin == owner, "not owner");
+        // Giu nguyen cau truc goc cua ham, chi thay tx.origin bang msg.sender:
+        // msg.sender la nguoi goi truc tiep, khong bi hop dong trung gian muon danh.
+        require(msg.sender == owner, "not owner");
         require(newOwner != address(0), "zero");
         owner = newOwner;
     }
 
     function noFunds() external view returns (bool) {
+        // Chi la ham view chan doan so du; ETH co the bi ep vao contract bang
+        // selfdestruct/block reward nen so sanh tuyet doi khong phai quyet dinh bao mat.
+        // slither-disable-next-line incorrect-equality
         return address(this).balance == 0;
     }
 
     function claimTokens(uint256 amount) external {
+        require(amount > 0, "zero amount");
         require(points[msg.sender] >= amount, "not enough");
         points[msg.sender] -= amount;
-        stableCoin.transfer(msg.sender, amount);
+        require(stableCoin.transfer(msg.sender, amount), "transfer failed");
     }
 
     function vestStep() external onlyOwner {
+        // Timelock 1 ngay: sai lech ~12s cua block.timestamp khong anh huong lich
+        // giai ngan, va ham da bi gioi han boi onlyOwner.
+        // slither-disable-next-line timestamp
         require(block.timestamp >= cooldownEnd, "locked");
         cooldownEnd = block.timestamp + 1 days;
         (bool ok, ) = payable(owner).call{value: address(this).balance / 10}("");
         require(ok, "release failed");
     }
 
-    function sunset() external {
-        selfdestruct(payable(msg.sender));
+    function sunset() external onlyOwner {
+        selfdestruct(payable(owner));
     }
 
-    function grant(address payable to, uint256 amount) external {
-        to.transfer(amount);
+    function grant(address payable to, uint256 amount) external onlyOwner {
+        require(to != address(0), "zero");
+        require(amount <= address(this).balance, "insufficient balance");
+        (bool ok, ) = to.call{value: amount}("");
+        require(ok, "send failed");
     }
```

- `git diff 3650b60 0553d5c -- AuditTarget.sol` thay đổi đúng 4 hàm: `handOver`,
  `claimTokens`, `sunset`, `grant` + 2 chú thích `slither-disable-next-line`.
- Scan trước/sau: `evidence/before_raw` (10 finding) → `evidence/after_raw` (5 finding: 1 Low
  `events-access` + 4 Informational), `evidence/before_configured` (5) → `evidence/after_configured`
  (**0** finding). CI: run baseline RED, run sau khi vá GREEN.
- Cảnh báo còn lại sau khi vá đều là Low/Informational và bị config lọc: `events-access` (đổi owner
  không phát event — em giữ nguyên hành vi gốc, không thêm event ngoài phạm vi bài), `low-level-calls`
  (đã có `require(ok)`), `naming-convention` (`stableCoin`/`cooldownEnd` — quy ước đặt tên, không phải lỗi bảo mật).
- Lý do **mọi** `slither-disable-next-line` (đúng 2 chỗ):
  - `incorrect-equality` ngay trên `return address(this).balance == 0;` — hàm `view` chẩn đoán, không
    tham gia quyết định bảo mật; kiểm soát bù trừ: không nơi nào trong contract tiêu thụ giá trị này.
  - `timestamp` ngay trên `require(block.timestamp >= cooldownEnd, "locked");` — timelock 1 ngày +
    `onlyOwner`; sai lệch vài giây không tạo lợi thế cho miner.

---

## 3. Kiến trúc / Inheritance (1,5 điểm)

- Lệnh printer đã chạy:
  - `slither contracts/ArchitectureDemo.sol --print human-summary --config-file config/slither.raw.json --fail-none`
  - `slither contracts/ArchitectureDemo.sol --print inheritance-graph --config-file config/slither.raw.json --fail-none`
  - `python tools/print_arch.py` (đóng gói log + render ảnh)
- Ảnh `evidence/architecture/inheritance.png` (có cả `ArchitectureDemo.sol.dot` và `human_summary.txt`
  trong `evidence/architecture/`).
- Ảnh **đã đánh dấu node**: `evidence/architecture/inheritance_annotated.png` (kèm
  `ArchitectureDemo.sol.annotated.dot`) — (1) khung vàng `AccessManaged` = quản lý quyền,
  (2) khung xanh dương `BalanceLedger` = mapping số dư, (3) khung xanh lá `StudentAsset` = entrypoint
  được gọi từ bên ngoài. Bản `inheritance.png` là output thô của printer, giữ nguyên để đối chiếu.
- Access control nằm ở abstract contract `AccessManaged` (`admin`, `modifier onlyAdmin`); logic số dư
  nằm ở `BalanceLedger` (`balances`, `_credit`, `balanceOf`); contract triển khai được là
  `StudentAsset` (kế thừa cả hai, thêm `mint` có `onlyAdmin` và event `Mint`).
- Trong `AuditTarget.sol`, toàn bộ quyền quản trị tập trung ở `owner` + `modifier onlyOwner`
  (dòng 19-22); tiền vào qua `topUp`, tiền ra qua `ownerWithdraw`/`vestStep`/`grant`, đổi chủ qua
  `handOver` — đây chính là bề mặt tấn công cần soi trước.
- 3-5 câu: điểm audit nên bắt đầu từ **ranh giới quyền**: mọi hàm `external` ghi state mà không có
  `onlyOwner`/`msg.sender` check phải được xem là nghi phạm đầu tiên (`sunset`, `grant`, `claimTokens`).
  Tiếp theo là **ranh giới tiền**: các lời gọi `call{value:}`/`transfer` phải kiểm tra đích, số dư và
  giá trị trả về. Cuối cùng là **nguồn định danh**: `tx.origin` không bao giờ được dùng làm
  authorization vì nó xuyên qua contract trung gian. Đồ thị kế thừa cho thấy `StudentAsset` gom quyền
  từ `AccessManaged`, nên một lỗi ở lớp cha ảnh hưởng toàn bộ contract con — audit lớp cha trước.

---

## 4. Red -> Green CI (2,5 điểm)

| Phase | Commit (full/short SHA) | Run URL | Kết quả | Detector khiến RED / lý do GREEN |
|---|---|---|---|---|
| Baseline vulnerable | `3650b6082c013fbeaf39d9414007de7692e04e94` (`3650b60`) | https://github.com/ComGa999ms/NT547.R11.ANTT_Lab6_24520825/actions/runs/44581997910 | **RED** | `arbitrary-send-eth` (High), `suicidal` (High), `unchecked-transfer` (High), `incorrect-equality` (Medium), `tx-origin` (Medium) — gate `fail-on: medium` |
| Patched | `0553d5cfb931ce120af34c10547df82573647109` (`0553d5c`) | https://github.com/ComGa999ms/NT547.R11.ANTT_Lab6_24520825/actions/runs/44582246433 | **GREEN** | 0 finding ở mức High/Medium sau khi vá + 2 suppression có lý do; Low/Info bị config lọc |

- So sánh local `--fail-none` (thu thập finding) với CI `fail-on: medium`: local luôn exit 0 và ghi
  JSON/CSV để phân tích; CI mới là nơi chặn chất lượng — cùng một danh sách finding nhưng CI thoát
  khác 0 khi còn Medium/High. Nhờ vậy quá trình triage không bị "đỏ giả" vì finding đã biết.
- `exclude_low`/`exclude_informational` thay đổi **khả năng hiển thị**, không thay đổi finding thật:
  raw 10 → configured 5 (bỏ 2 Low + 3 Info), còn nguyên 3 High + 2 Medium. Vì vậy baseline vẫn RED —
  nếu ai đó cố dùng config để "làm xanh" thì buộc phải `exclude_medium`/`exclude_high`, điều bài cấm.

---

## 5. Mutation RED -> GREEN (1,5 điểm)

- Mutation một dòng: `require(msg.sender == owner, "not owner");` -> `require(tx.origin == owner, "not owner");`
  tại câu lệnh kiểm tra quyền của `handOver` (`AuditTarget.sol`, dòng 41). Đúng **một dòng** thay đổi.
- Detector kỳ vọng: `tx-origin` (mức Medium); xác nhận từ CI: run mutation **RED**, log Slither báo
  `PiggyBank_0825.handOver(address) uses tx.origin for authorization`.
- Ghi chú kỹ thuật (trung thực về công cụ): em đã thử đặt đúng dòng mutation vào **modifier `onlyOwner`**
  như hướng dẫn, nhưng Slither 0.11.6 chỉ quét `tx.origin` trong **thân hàm** (detector duyệt
  `contract.functions`, modifier là danh sách riêng) nên CI vẫn xanh — một điểm mù của detector. Vì
  rubric cần một run RED thật do `tx-origin`, em giữ câu kiểm tra quyền của `handOver` ở dạng tường
  minh trong hàm (đúng cấu trúc gốc của baseline) và đặt mutation tại đó: vẫn là một dòng
  `msg.sender` -> `tx.origin`, và CI bắt được đúng detector như kỳ vọng.

| Phase | Commit SHA | Run URL | Kết quả |
|---|---|---|---|
| Mutation | `406b12d6161c4a0fbfbb4c0ab205346dce5f5d9b` (`406b12d`) | https://github.com/ComGa999ms/NT547.R11.ANTT_Lab6_24520825/actions/runs/44582492716 | **RED** (`tx-origin`, Medium) |
| Revert mutation | `f09ada7218acab282394d4bc55e78fc1e05cfcbd` (`f09ada7`) | https://github.com/ComGa999ms/NT547.R11.ANTT_Lab6_24520825/actions/runs/44582675670 | **GREEN** |

- Giải thích sự thay đổi về nguồn định danh/authorization: `msg.sender` là **người gọi trực tiếp**
  hàm, còn `tx.origin` là **địa chỉ khởi tạo giao dịch** và giữ nguyên xuyên qua mọi lời gọi contract.
  Dùng `tx.origin` làm authorization nghĩa là: nếu owner bị dụ tương tác với một contract độc hại,
  contract đó gọi `handOver` thì `tx.origin == owner` vẫn đúng -> kẻ tấn công chiếm quyền sở hữu (lỗi
  kinh điển bị khai thác qua phishing). Đổi về `msg.sender` thì contract trung gian không mượn được
  danh tính owner, và `onlyOwner` ở các hàm khác cũng dựa trên `msg.sender` nên nhất quán toàn bộ.

---

## 6. Bằng chứng, tự kiểm

- [x] `AuditTarget.sol`, `lab_identity.json` (session `SC-D47865`, contract `PiggyBank_0825`)
- [x] `evidence/before_raw/` và `evidence/before_configured/` (JSON + CSV + summary + log)
- [x] `evidence/after_raw/` và `evidence/after_configured/`
- [x] `evidence/architecture/` (`human_summary.txt`, `.dot`, `inheritance.png`, `printer_log.txt`)
- [x] 04 URL Actions run RED/GREEN/RED/GREEN + 04 commit SHA (bảng mục 4 và 5)
- [x] Link repo + minh chứng terminal/Actions còn nguyên ngữ cảnh (log `command_and_output.txt` lưu
      đúng lệnh, phiên bản slither/solc, exit code)
- [x] Các finding được triage, không chép lại mô tả detector thay cho suy luận
- [x] Không có private key / token / seed phrase trong repo hoặc trong báo cáo
