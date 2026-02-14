# 增量 JSON 解析 BDD 场景
# 覆盖 Gong.PartialJson 的完整解析、补全、累积

[SCENARIO: PJSON-001] TITLE: 完整 JSON 直接解析 TAGS: unit partial_json
WHEN partial_json_parse input="{\"a\":1}"
THEN assert_partial_json_ok
THEN assert_partial_json_field key="a" expected="1"

[SCENARIO: PJSON-002] TITLE: 未闭合字符串补全 TAGS: unit partial_json
WHEN partial_json_parse input="{\"file\":\"/src/ma"
THEN assert_partial_json_has_key key="file"

[SCENARIO: PJSON-003] TITLE: 未闭合对象补全 TAGS: unit partial_json
WHEN partial_json_parse input="{\"a\":1,\"b\":2"
THEN assert_partial_json_has_key key="a"
THEN assert_partial_json_has_key key="b"

[SCENARIO: PJSON-004] TITLE: 嵌套对象补全 TAGS: unit partial_json
WHEN partial_json_parse input="{\"outer\":{\"inner\":1"
THEN assert_partial_json_has_key key="outer"

[SCENARIO: PJSON-005] TITLE: 数组补全 TAGS: unit partial_json
WHEN partial_json_parse input="{\"items\":[1,2,3"
THEN assert_partial_json_has_key key="items"

[SCENARIO: PJSON-006] TITLE: 空输入返回空 map TAGS: unit partial_json
WHEN partial_json_parse input=""
THEN assert_partial_json_empty

[SCENARIO: PJSON-007] TITLE: 累积多片段合并 TAGS: unit partial_json
WHEN partial_json_accumulate chunk1="{%name%:%he" chunk2="llo" chunk3="%}"
THEN assert_partial_json_field key="name" expected="hello"

[SCENARIO: PJSON-008] TITLE: 尾部逗号容错 TAGS: unit partial_json
WHEN partial_json_parse input="{\"a\":1,"
THEN assert_partial_json_has_key key="a"
