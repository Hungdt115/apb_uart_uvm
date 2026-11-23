# Hướng dẫn biên tập spec — APB UART

## Cách làm việc

Mỗi trang spec có 2 file **cùng thư mục, cùng tên**:

- `.html` — trang hiển thị chính thức. Mở trực tiếp bằng trình duyệt (double-click), không server, không fetch.
- `.md` — bản nội dung dễ biên tập (markdown, không dính tag HTML). Sửa nội dung ở `.md` rồi cập nhật sang `.html`, hoặc sửa thẳng `.html`.

Nội dung hiện tại là bản thô — ưu tiên hình thức, chưa quan tâm nội dung.

## Cấu trúc trang

- `index.html` / `index.md` — spec của **top module** (uart top): overview, features, block diagram,
  bảng instances link tới trang từng submodule, port list, register map tóm tắt.
- `spec/<module>_spec.html` / `.md` — mỗi submodule một trang.

## Cách thêm submodule mới (ví dụ sync_fifo)

1. Copy cặp file có sẵn (ví dụ `spec/apb_slave_spec.html` + `.md`) → đổi tên, sửa nội dung.
2. Thêm **1 dòng** vào `js/nav.js` → sidebar "Submodules" của mọi trang tự có link.
3. Thêm 1 dòng vào bảng "Submodule Instances" của `index.html` (và `index.md`) để có link từ trang top.

## Sidebar

- Nhãn nhóm `.nav-section` có nền highlight, ngăn cách bằng viền kẻ.
- Item trong trang được `nav.js` tự đánh số `01, 02, …` và thụt lề so với nhãn — không cần ghi số trong HTML.
- Menu "Submodules" (link chéo trang) lấy từ `js/nav.js`, trang đang mở được tô sáng.
- Badge RTL ở đầu trang là link mở thẳng file nguồn (`.v`) tương ứng.

## Các class dùng chung (trong css/spec.css)

| Mục đích | Class |
|---|---|
| Bảng | `.table-wrap` > `table` |
| Access badge / màu bit strip | `.acc-rw` `.acc-ro` `.acc-wo` `.acc-w1c` `.acc-rsvd` / `.seg-*` |
| Hướng port / cực reset | `.dir-in` `.dir-out` `.dir-inout` · `.active-low` `.active-high` |
| Register card | `.reg-block` > `.reg-header` + `.bitfield` (các `.bit-seg` xếp MSB→LSB, `flex` tỷ lệ số bit) + `.reg-field-table` |
| Sidebar | `.nav-group` (nhãn highlight) · `.nav-num` (số thứ tự item) |
| Khác | `.badge` `.notice` `.legend` `.features` `pre.timing` |

## Quy ước viết

- Mô tả tiếng Anh, khớp comment RTL.
- Hex ghi dạng `0x…`, dùng `_` phân nhóm chữ số (`0x0000_003F`).
- Reserved bits: không vẽ từng bit, gộp thành một segment `RSVD`.
- Cột bảng port cố định: Signal · Dir · Width · Clock · Active · Description.
