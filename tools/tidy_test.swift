// 띄어 읽힌 인증번호 붙이기(Recognizer.tidyDigits) 확인. run_tests.sh가 main.swift로 복사해 Recognizer.swift와 함께 컴파일한다
import Foundation

let cases: [(String, String)] = [
    ("4829 1 3", "482913"), ("48291 3", "482913"), ("4 8 2 9 1 3", "482913"), ("12 3 4", "1234"),
    ("010 1234 5678", "010 1234 5678"),   // 전화번호: 덩이가 고름
    ("1234 5678", "1234 5678"),           // 한 자리 덩이 없음
    ("482913", "482913"), ("A 1 2 3 4", "A 1 2 3 4"), ("1 2 3", "1 2 3"), ("1 2 3 4 5 6 7 8 9", "1 2 3 4 5 6 7 8 9"),
]
var fail = 0
for (input, want) in cases {
    let r = Recognizer.tidyDigits(Recognized(lines: [[Piece(rect: .zero, text: input)]], table: nil))
    let ok = r.text == want
    if !ok { fail += 1 }
    print("\(ok ? "✓" : "✗") \"\(input)\" → \"\(r.text)\"\(ok ? "" : " (기대 \"\(want)\")")")
}
print(fail == 0 ? "모두 통과" : "\(fail)개 실패")
exit(fail == 0 ? 0 : 1)
