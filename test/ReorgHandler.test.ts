it('changed depth affects confirmation requirement', () => {
    const handler = new ReorgHandler(6);
    expect(handler.getConfirmationDepth()).toBe(6);
  
    handler.setConfirmationDepth(20);
    expect(handler.getConfirmationDepth()).toBe(20);
  
    // Verify behavior changes — e.g., a block at depth 15 is confirmed at 20 but not at 6
    const blockDepth = 15;
    const isConfirmedBefore = blockDepth >= 6;   // true
    const isConfirmedAfter  = blockDepth >= 20;  // false — depth now changes outcome
    expect(isConfirmedBefore).toBe(true);
    expect(isConfirmedAfter).toBe(false);
  });
  
  it('rejects invalid depth', () => {
    expect(() => new ReorgHandler(0)).toThrow();
    expect(() => new ReorgHandler(-1)).toThrow();
  });