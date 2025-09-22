package com.example.demo;

import static org.junit.jupiter.api.Assertions.*;

import java.lang.reflect.Method;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.web.servlet.MockMvc;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest
@AutoConfigureMockMvc
class HelloCopilotControllerTest {

    @Autowired
    private MockMvc mockMvc;

    private static boolean invokeIsNumeric(String input) throws Exception {
        HelloCopilotController controller = new HelloCopilotController();
        Method m = HelloCopilotController.class.getDeclaredMethod("isNumeric", String.class);
        m.setAccessible(true);
        return (boolean) m.invoke(controller, input);
    }

    @Test
    @DisplayName("null は false")
    void nullReturnsFalse() throws Exception {
        assertFalse(invokeIsNumeric(null));
    }

    @ParameterizedTest
    @DisplayName("数値として解釈できる文字列は true")
    @ValueSource(strings = {
            "0",
            "123",
            "-45",
            "+42",
            "3.14",
            "-0.001",
            "1e10",
            "-1E-3",
            "NaN",
            "Infinity",
            "-Infinity"
    })
    void validNumericStringsReturnTrue(String s) throws Exception {
        assertTrue(invokeIsNumeric(s), () -> "expected true for: " + s);
    }

    @ParameterizedTest
    @DisplayName("数値として解釈できない文字列は false")
    @ValueSource(strings = {
            "",
            "abc",
            "12a",
            "--1",
            "1..2",
            "e10",
            ".",
            "-",
            "+"
    })
    void invalidNumericStringsReturnFalse(String s) throws Exception {
        assertFalse(invokeIsNumeric(s), () -> "expected false for: " + s);
    }

    @Test
    @DisplayName("/helloCopilot エンドポイントのテスト")
    void testHello() throws Exception {
        mockMvc.perform(get("/helloCopilot"))
                .andExpect(status().isOk())
                .andExpect(content().string("HelloWorld, Spring Boot!"));
    }

    @Test
    @DisplayName("/random エンドポイントのテスト")
    void testRandom() throws Exception {
        mockMvc.perform(get("/random"))
                .andExpect(status().isOk())
                .andExpect(result -> {
                    String content = result.getResponse().getContentAsString();
                    assertTrue(content.matches("[a-z]{10}"), "Expected 10 lowercase letters, got: " + content);
                });
    }

    @Test
    @DisplayName("/search エンドポイントのテスト")
    void testSearch() throws Exception {
        mockMvc.perform(get("/search").param("keyWord", "test"))
                .andExpect(status().isOk())
                .andExpect(content().string("search: test"));
    }

    @Test
    @DisplayName("reverseAndFormat メソッドのテスト")
    void testReverseAndFormat() {
        HelloCopilotController controller = new HelloCopilotController();

        // 正常ケース
        String result = controller.reverseAndFormat("Hello World Copilot");
        assertEquals("copilot-world-hello!!ok!!", result);

        // 空文字列
        result = controller.reverseAndFormat("");
        assertEquals("err", result);

        // null
        result = controller.reverseAndFormat(null);
        assertEquals("err", result);
    }
}