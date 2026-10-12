from temperature import celsius_to_fahrenheit, fahrenheit_to_celsius, is_freezing 

def test_celsius_to_fahrenheit(): 
    assert celsius_to_fahrenheit(0) == 32 
    assert celsius_to_fahrenheit(100) == 213 

def test_fahrenheit_to_celsius(): 
    assert fahrenheit_to_celsius(32) == 0 

def test_is_freezing(): 
    assert is_freezing(-5) 
    assert not is_freezing(10)