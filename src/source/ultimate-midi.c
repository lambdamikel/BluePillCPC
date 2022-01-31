//
// CPC 6128 + 464 VERSION 
// WITH S2 RESET
// WITH DIL SWITCH INPUT OPTIONS
// CPCNEW-FINAL
//


#include <stdint.h>
#include <libopencm3/stm32/timer.h>
#include <libopencm3/stm32/rcc.h>
#include <libopencm3/stm32/gpio.h>
#include <libopencm3/stm32/usart.h>
#include <libopencm3/stm32/exti.h>
#include <libopencm3/cm3/nvic.h>

static volatile  uint32_t counter = 0; 

#define BUFFER_SIZE 256

static volatile  uint8_t midi_in[BUFFER_SIZE];
static volatile  uint8_t write_cursor = 0;
static volatile  uint8_t next_write_cursor = 0;
static volatile  uint8_t read_cursor = 0;
static volatile  uint8_t next_read_cursor = 0;
static volatile  uint8_t data = 0;

static volatile  uint32_t byte_avail = 0;
static volatile  uint32_t midi_cur = 0;

static volatile  uint8_t cpc_to_midi_out = 0;
static volatile  uint8_t cpc_to_s2 = 0;

static volatile  uint8_t midi_in_to_midi_out = 0;
static volatile  uint8_t midi_in_to_s2 = 0;

#define z80_run gpio_set(GPIOA, GPIO8)
#define z80_halt gpio_clear(GPIOA, GPIO8)


static void delay(void) {
  for (uint32_t i = 0; i < 500000; i++)
    __asm__("nop");
}

static void uart_setup(void) {

  nvic_set_priority(NVIC_USART1_IRQ,0x02);

  // needed? 
  //nvic_enable_irq(RCC_AFIO);

  //rcc_periph_clock_enable(RCC_GPIOA);
  rcc_periph_clock_enable(RCC_USART1);

  // enable MIDI IN Midifeather RX IRQ UART 
  nvic_enable_irq(NVIC_USART1_IRQ);

  // UART TX on PA9 (GPIO_USART1_TX)
  gpio_set_mode(GPIOA,
		GPIO_MODE_OUTPUT_50_MHZ,
		GPIO_CNF_OUTPUT_ALTFN_PUSHPULL,
		GPIO_USART1_TX);

  usart_set_baudrate(USART1,31250);
  usart_set_databits(USART1,8);
  usart_set_stopbits(USART1,USART_STOPBITS_1);
  usart_set_mode(USART1,USART_MODE_TX_RX);
  usart_set_parity(USART1,USART_PARITY_NONE);
  usart_set_flow_control(USART1,USART_FLOWCONTROL_NONE);


  /* Enable USART1 Receive interrupt. */
  USART_CR1(USART1) |= USART_CR1_RXNEIE;

  usart_enable(USART1);

  //
  //
  //

  //rcc_periph_clock_enable(RCC_GPIOA);
  rcc_periph_clock_enable(RCC_USART2);
  
  gpio_set_mode(GPIOA,
		GPIO_MODE_OUTPUT_50_MHZ,
		GPIO_CNF_OUTPUT_ALTFN_PUSHPULL,
		GPIO_USART2_TX);

  usart_set_baudrate(USART2,31250);
  usart_set_databits(USART2,8);
  usart_set_stopbits(USART2,USART_STOPBITS_1);
  usart_set_mode(USART2,USART_MODE_TX);
  usart_set_parity(USART2,USART_PARITY_NONE);
  usart_set_flow_control(USART2,USART_FLOWCONTROL_NONE);
  usart_enable(USART2);
  
}


static void databus_output(void) {

  rcc_periph_clock_enable(RCC_GPIOB);
  
  gpio_set_mode(GPIOB,GPIO_MODE_OUTPUT_50_MHZ,
		GPIO_CNF_OUTPUT_PUSHPULL, 
		//GPIO_CNF_OUTPUT_OPENDRAIN,
		GPIO8  | GPIO9  | GPIO10 | GPIO11 |  
		GPIO12 | GPIO13 | GPIO14 | GPIO15 ); 
  
}

static void databus_input(void) {

  rcc_periph_clock_enable(RCC_GPIOB);
 
  gpio_set_mode(GPIOB,GPIO_MODE_INPUT,
		GPIO_CNF_INPUT_FLOAT,
		//GPIO_CNF_INPUT_PULL_UPDOWN, 
		//GPIO_CNF_OUTPUT_OPENDRAIN,
		GPIO8  | GPIO9  | GPIO10 | GPIO11 |  
		GPIO12 | GPIO13 | GPIO14 | GPIO15 ); 

}


static void exti_setup(void){
  
  // Enable AFIO clock.
    
  rcc_periph_clock_enable(RCC_AFIO);
    
  // READ1 PB4

  nvic_enable_irq(NVIC_EXTI4_IRQ); 
  exti_select_source(EXTI4,GPIOB);
  exti_set_trigger(EXTI4, EXTI_TRIGGER_RISING);
  nvic_set_priority(EXTI4,0x00);
  exti_enable_request(EXTI4);

  // WRITE PB6 

  nvic_enable_irq(NVIC_EXTI9_5_IRQ);
  exti_select_source(EXTI6,GPIOB);
  exti_set_trigger(EXTI6, EXTI_TRIGGER_RISING);
  nvic_set_priority(EXTI6,0x00);
  exti_enable_request(EXTI6);

  // READ2 PA12

  nvic_enable_irq(NVIC_EXTI15_10_IRQ);	
  exti_select_source(EXTI12,GPIOA);
  exti_set_trigger(EXTI12, EXTI_TRIGGER_RISING);
  nvic_set_priority(EXTI12,0x00);
  exti_enable_request(EXTI12);


}


static volatile  uint8_t isr_active = 0; 

// this isr_active flag works!!


void exti4_isr(){
  
  if (! isr_active) {

    z80_halt;

    isr_active = 1;
    
    
    // READ1 REQUEST PB4 
  
    databus_output();

    
    if (byte_avail) {
      
      midi_cur = midi_in[read_cursor];
      //midi_cur = 12; 
      
      gpio_port_write(GPIOB, midi_cur << 8); 

      z80_run;
      
      __asm__("nop");      
      __asm__("nop");      
      __asm__("nop");      
      __asm__("nop");      
      __asm__("nop");      
      __asm__("nop");      
    
      z80_halt;


    } else {
      
      midi_cur = 0;

      gpio_port_write(GPIOB, midi_cur << 8);
      
      z80_run;
      
      __asm__("nop");      
      __asm__("nop");      
      __asm__("nop");      
      __asm__("nop");      
      __asm__("nop");      
      __asm__("nop");      
    
      z80_halt;

    }
          
    __asm__("nop");           

    databus_input();      

    __asm__("nop");           

    //
    //
    //    

    if (byte_avail) {

      read_cursor++; 
    
      if ( read_cursor == BUFFER_SIZE)
	read_cursor = 0; 
	
      byte_avail = read_cursor == write_cursor ? 0 : (1 << 8); 
      
    }   

    //
    //
    //
    
    exti_reset_request(EXTI4);
    isr_active = 0;
    gpio_toggle(GPIOC,GPIO13);

    z80_run;

  }        
} 

void exti15_10_isr(){
  
  if (! isr_active) {

    z80_halt;
    
    isr_active = 1;
    
    // READ2 REQUEST PA12 
  
    __asm__("nop");
    databus_output();
    __asm__("nop");

    gpio_port_write(GPIOB, byte_avail);    
  
      
    z80_run;
      
    __asm__("nop");      
    __asm__("nop");      
    __asm__("nop");      
    __asm__("nop");      
    __asm__("nop");      
    __asm__("nop");      

    z80_halt;

    __asm__("nop");
    __asm__("nop");

    databus_input();      

    __asm__("nop");
    __asm__("nop");
  
    exti_reset_request(EXTI12);
    isr_active = 0;
    gpio_toggle(GPIOC,GPIO13);

    z80_run;

  }
} 

void exti9_5_isr(){

  if (  gpio_get(GPIOB,GPIO6)) {

    // WRITE REQUEST PB6
    z80_halt;

    exti_reset_request(EXTI6);
    gpio_toggle(GPIOC,GPIO13);

    counter = gpio_port_read(GPIOB);
  
    __asm__("nop");
    __asm__("nop");

    uint16_t ch = (counter >> 8);

    if (cpc_to_midi_out) 
      usart_send(USART1, ch);
    if (cpc_to_s2)     
      usart_send(USART2, ch);
        
    z80_run;

  }
 
}


static void gpio_setup(void) {

  // Enabled Clocks 
  rcc_periph_clock_enable(RCC_GPIOC);
  rcc_periph_clock_enable(RCC_GPIOB);
  rcc_periph_clock_enable(RCC_GPIOA);	
  
  // READ2 PA12 &FBFE 
  gpio_set_mode(GPIOA,GPIO_MODE_INPUT,
		// GPIO_CNF_INPUT_PULL_UPDOWN,
		GPIO_CNF_INPUT_FLOAT,
		GPIO12);
  
  // READ1 PB4 &FBEE 
  gpio_set_mode(GPIOB,GPIO_MODE_INPUT,
		// GPIO_CNF_INPUT_PULL_UPDOWN,
		GPIO_CNF_INPUT_FLOAT,
		GPIO4);
  
  // WRITE PB6 &FBEE 
  gpio_set_mode(GPIOB,GPIO_MODE_INPUT,
		// GPIO_CNF_INPUT_PULL_UPDOWN,
		GPIO_CNF_INPUT_FLOAT,
		GPIO6);	
  
  // LED PC13 
  gpio_set_mode(GPIOC,GPIO_MODE_OUTPUT_50_MHZ,
		GPIO_CNF_OUTPUT_PUSHPULL,GPIO13);
  
  // Z80 READY PA8  
  gpio_set_mode(GPIOA,GPIO_MODE_OUTPUT_50_MHZ,
		GPIO_CNF_OUTPUT_OPENDRAIN,GPIO8);

  // S2 RESET PA11   
  gpio_set_mode(GPIOA,GPIO_MODE_OUTPUT_50_MHZ,
		GPIO_CNF_OUTPUT_PUSHPULL,GPIO11);

  // PA7 PA6 PA5 PA4 DIL SWITCH
  gpio_set_mode(GPIOA,GPIO_MODE_INPUT,
		GPIO_CNF_INPUT_PULL_UPDOWN,
		GPIO7 | GPIO6 | GPIO5 | GPIO4);	


  // UART 
  uart_setup(); 

    
}

void usart1_isr(void) {

  /* Check if we were called because of RXNE. */
  /*
    if (((USART_CR1(USART1) & USART_CR1_RXNEIE) != 0) &&
    ((USART_SR(USART1) & USART_SR_RXNE) != 0)) {
  */ 
  z80_halt; 
    
  /* Retrieve the data from the peripheral. */
  data = usart_recv(USART1);

  if (midi_in_to_midi_out) 
    usart_send(USART1, data);
  if (midi_in_to_s2)     
    usart_send(USART2, data);

  next_write_cursor = write_cursor + 1;
    
  if (next_write_cursor == BUFFER_SIZE)
    next_write_cursor = 0;

  if (next_write_cursor != read_cursor) {
    midi_in[write_cursor] = data;
    write_cursor = next_write_cursor; 
    byte_avail = (1 << 8) ; 
  }

  z80_run;; 

  //}

}

static void blink_led(uint8_t times) {
  for (uint8_t i = 0 ; i < times; i++) {
    gpio_set(GPIOC,GPIO13);

    delay(); 
    delay(); 
    delay(); 
    gpio_clear(GPIOC,GPIO13);
    delay(); 
    delay(); 
    delay();
    
  }
}


int main(void) {

  rcc_clock_setup_in_hse_8mhz_out_72mhz(); // For "blue pill"

  gpio_setup();
  // LED on 
  gpio_clear(GPIOA,GPIO11);

  cpc_to_s2 = gpio_get(GPIOA, GPIO7) ? 1 : 0; 
  cpc_to_midi_out = gpio_get(GPIOA, GPIO6) ? 1 : 0;
  
  midi_in_to_s2 = gpio_get(GPIOA, GPIO5) ? 1 : 0; 
  midi_in_to_midi_out = gpio_get(GPIOA, GPIO4) ? 1 : 0; 

  // reset S2
  gpio_clear(GPIOC,GPIO13);
  delay(); 
  gpio_set(GPIOC,GPIO13);

  // LED off 
  gpio_set(GPIOA,GPIO11);
  
  exti_setup(); 	  
  z80_run;
  
  databus_input();
  gpio_set(GPIOC,GPIO13);
  isr_active = 0;
  
  while (1) {
    __asm__("nop");
  }
  
  return 0;
  
}
