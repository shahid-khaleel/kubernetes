package com.shahidkhaleel.cicddemo.service;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;

class VisitCounterServiceTest {

    private final VisitCounterService visitCounterService = new VisitCounterService();

    @Test
    void startsAtZero() {
        assertThat(visitCounterService.current()).isZero();
    }

    @Test
    void incrementsOnEachCall() {
        assertThat(visitCounterService.incrementAndGet()).isEqualTo(1);
        assertThat(visitCounterService.incrementAndGet()).isEqualTo(2);
        assertThat(visitCounterService.incrementAndGet()).isEqualTo(3);
    }

    @Test
    void currentReflectsLastIncrementWithoutAdvancing() {
        visitCounterService.incrementAndGet();
        visitCounterService.incrementAndGet();

        assertThat(visitCounterService.current()).isEqualTo(2);
        assertThat(visitCounterService.current()).isEqualTo(2);
    }
}
