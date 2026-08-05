package com.shahidkhaleel.cicddemo.service;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;

class GreetingServiceTest {

    private final GreetingService greetingService = new GreetingService();

    @Test
    void greetsProvidedName() {
        String greeting = greetingService.buildGreeting("Shahid");

        assertThat(greeting).startsWith("Hello, Shahid!");
    }

    @Test
    void fallsBackToWorldWhenNameIsNull() {
        String greeting = greetingService.buildGreeting(null);

        assertThat(greeting).startsWith("Hello, World!");
    }

    @Test
    void fallsBackToWorldWhenNameIsBlank() {
        String greeting = greetingService.buildGreeting("   ");

        assertThat(greeting).startsWith("Hello, World!");
    }

    @Test
    void trimsSurroundingWhitespace() {
        String greeting = greetingService.buildGreeting("  Shahid  ");

        assertThat(greeting).startsWith("Hello, Shahid!");
    }
}
