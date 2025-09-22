package com.example.demo;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * HelloCopilot 用の REST コントローラ。
 * <p>
 * 提供エンドポイント:
 * <ul>
 *   <li>GET /helloCopilot: 動作確認メッセージを返す</li>
 *   <li>GET /random: 英小文字のランダム10文字を返す</li>
 *   <li>GET /search?keyWord=...: 受け取ったクエリ文字列をエコーする</li>
 * </ul>
 * </p>
 */
@RestController
public class HelloCopilotController {
    /**
     * 動作確認用のエンドポイント。
     *
     * @return "HelloWorld, Spring Boot!" の固定メッセージ
     */
    @GetMapping("/helloCopilot")
    public String hello() {
        return "HelloWorld, Spring Boot!";
    }
    

    /**
     * 入力文字列を逆順に並べ替え、ハイフンで結合して特定の形式に変換する。
     *
     * @param input 入力文字列（null または空文字列はエラーとして処理）
     * @return 処理結果の文字列。エラーの場合は "err" を返す。
     */
    public String reverseAndFormat(String input) {
        // null または空文字列の場合はエラーを返す
        if (input == null || input.isEmpty()) {
            return "err";
        }

        // 入力文字列をスペースで分割
        String[] words = input.split(" ");

        // 単語を逆順に並べ替え、ハイフンで結合
        StringBuilder formattedResult = new StringBuilder();
        for (int i = words.length - 1; i >= 0; i--) {
            String word = words[i];
            formattedResult.append(word.toLowerCase()); // 小文字に変換
            if (i != 0) {
                formattedResult.append("-");
            }
        }

        // 最後に固定文字列を追加
        formattedResult.append("!!ok!!");
        return formattedResult.toString();
    }
    
    
    /**
     * 英小文字 [a-z] からなる長さ10のランダム文字列を生成して返す。
     *
     * @return 10文字のランダム文字列
     */
    @GetMapping("/random")
    public String random() {
    	int leftLimit = 97; // letter 'a'
		int rightLimit = 122; // letter 'z'
		int targetStringLength = 10;
		StringBuilder buffer = new StringBuilder(targetStringLength);
		for (int i = 0; i < targetStringLength; i++) {
			int randomLimitedInt = leftLimit + (int) (Math.random() * (rightLimit - leftLimit + 1));
			buffer.append((char) randomLimitedInt);
		}
		String generatedString = buffer.toString();
		return generatedString;
    }
    
    /**
     * 文字列が数値として解釈可能かどうかを判定する。
     *
     * @param str 判定対象の文字列（null 可）
     * @return 数値の場合は true、そうでない場合は false
     */
    private boolean isNumeric(String str) {
		if (str == null) {
			return false;
		}
		try {
			Double.parseDouble(str);
			return true;
		} catch (NumberFormatException e) {
			return false;
		}
	}
    
    /**
     * GET で keyWord クエリパラメータを受け取り、その内容をそのまま返すシンプルな検索サンプル。
     *
     * 例: /search?keyWord=spring
     *
     * @param keyWord 検索キーワード（必須）
     * @return 受け取ったキーワードを含む応答文字列
     */
    @GetMapping("/search")
    public String search(@RequestParam("keyWord") String keyWord) {
        return "search: " + keyWord;
    }
}