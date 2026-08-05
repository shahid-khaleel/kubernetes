package com.shahidkhaleel.cicddemo;

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;

@SpringBootTest
class CicdDemoApplicationTests {

    @Test
    void contextLoads() {
        // Fails the build if the Spring application context can't start —
        // the cheapest possible smoke test for wiring/config mistakes.
    }
}
